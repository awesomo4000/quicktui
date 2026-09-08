# QuickTUI consumer integration improvements

Date: 09/07/2026

Status: QuickTUI implementation complete in the working tree; not yet committed.
Archived: 09/08/2026.

This work makes QuickTUI usable by independently developed terminal applications.
Application-specific protocol changes and consumer migration remain outside this
completed QuickTUI scope. The requirements below preserve the original proposal;
the completion record identifies what was implemented and tested.

## Completion record

- Endpoint lifecycle: explicit send/receive outcomes, one-time disconnect delivery,
  removal of failed descriptors from polling, and bounded draining after hangup.
- Application startup: public `mountApp` and Zig `runApp`, with application-owned
  shortcuts and documented key consumption, message delivery, and cleanup.
- Text paste: a dedicated literal-text callback, a 1 MiB payload bound, overflow
  discard through the closing delimiter, and cleanup of incomplete paste input.
- Consumer bundling: `bundleApp` and its CLI own runtime substitutions, public
  import resolution, unsupported host-import errors, license inclusion, and
  optional external source maps. There is one fixed native registry today.
- Independent example: builds outside the checkout using documented entry points,
  with the same application API in headless and interactive tests.

Validation passed for the existing Zig/demo suite, disposable endpoint stress
fixtures, full-reply-queue shutdown, fragmented and oversized paste cases, bundler
checks, and an external consumer build with a real PTY smoke test. The endpoint
fixtures cover sustained traffic, resize/input/quit progress, closure notification,
queued replies during hangup, and prevention of callbacks after closure.

Repeated teardown tests are regression coverage, not a comprehensive proof of
allocation or descriptor leak freedom. Arbitrarily slow JavaScript callbacks are
not preempted. Source maps are available to external tools; QuickJS exception
stacks still report generated positions.

See the [application contract](../../docs/application-api.md),
[independent example](../../examples/consumer/),
[endpoint fixtures](../../src/endpoint_tests.c),
[PTY stress test](../../scripts/test-endpoint-terminal.py), and
[paste tests](../../tests/paste.test.ts).

Programmatic clipboard permissions and image paste remain deferred. Incoming
terminal paste is a separate interface and grants no clipboard-read capability.
This work does not establish an untrusted-JavaScript security boundary.

Storage, SQLite, and Fossil are parked separately. Dynamic JavaScript loading is not required for this work.

## Original integration context

The consumer's Zig executable consumes QuickTUI's exported library module. Its JavaScript integration is less independent:

- The consumer bundler adapts QuickTUI's bundler, including runtime import replacements, unsupported host-module handling, native binding adjustments, and license collection.
- The consumer application imports `mountDemo`, `keys`, and `interceptKeys` directly from QuickTUI's `js/platform/demo` module, along with internal bootstrap and vendored React paths.
- The consumer's native transport uses QuickTUI's message endpoint to exchange copied strings with a worker. Socket I/O happens off the UI thread.
- The consumer currently requests state and events periodically. QuickTUI's native message mechanism can deliver unsolicited messages, but the consumer's socket protocol and transport do not yet implement subscriptions.

The original arrangement worked. The maintenance problem was that the consumer knew QuickTUI's internal file layout and duplicated build logic that QuickTUI should own.

## 1. Handle message-endpoint failure explicitly

The reviewed `src/app_host.c` event loop handles terminal input hangup/error flags, but does not give the message endpoint's wake descriptor equivalent explicit handling for `POLLHUP`, `POLLERR`, and `POLLNVAL`.

A descriptor that continually reports one of these conditions could cause repeated immediate wakeups. This is a suspected failure mode, not a reproduced busy-loop bug.

Define the endpoint lifecycle contract: what closure means, how the application learns about it, and whether the UI stays open in a disconnected state. Stop polling an unusable descriptor rather than treating it as ordinary incoming data.

Acceptance tests:

- Close a disposable worker endpoint while the UI is idle and while messages are queued.
- Exercise invalid/error descriptor handling using controlled test fixtures.
- Verify no tight polling loop, repeated error storm, use-after-free, or hang on quit.
- Verify the client receives a bounded, understandable failure notification.

## 2. Test message fairness under sustained load

The reviewed host processes messages in batches of up to 32. A batch limit is useful, but does not by itself prove that input, rendering, timers, and resize handling stay responsive under continuous traffic.

Add a deterministic producer that sends bursts larger than one batch and a sustained stream. Interleave keyboard input, resize events, timers, and quit requests. Verify ordered delivery where promised, bounded queues, and progress for every event source.

Document backpressure behavior. A producer must be able to distinguish accepted messages from a full or closed queue. Do not silently drop application events. Coalescing replaceable display updates should be an explicit application choice.

## 3. Test shutdown with full queues

Exercise shutdown when a worker is blocked or retrying because its reply queue is full. Include shutdown during incoming traffic and during a pending request.

Acceptance criteria:

- Cancellation wakes blocked work and allows worker joins to finish.
- Queue storage and wake descriptors remain valid until their users stop.
- Ownership of accepted and rejected message buffers is documented and tested.
- Repeated startup/shutdown does not leak descriptors or allocations.

These are additional regression targets, not a claim that all these failure modes currently occur.

## 4. Expose bracketed paste as an application event

The consumer originally supplied a local bracketed-paste adapter because the demo input adapter does not expose paste in the form its composer needed.

QuickTUI should expose a supported paste event containing literal text, separate from key events. Pasting a slash command or newline must not accidentally execute it. The application decides whether and when to submit.

Test fragmented paste delimiters, Unicode, multiline text, size limits, incomplete escape sequences, and cleanup on shutdown. Applications should not need to replace internal input hooks to handle paste.

## 5. Provide a supported consumer bundler

Expose a build command or library function that accepts an application entry point and output path. QuickTUI should own its runtime substitutions and compatibility shims, rather than asking each consumer to copy and maintain them.

The consumer contract should cover:

- TSX/React bundling for QuickTUI's JavaScript runtime.
- Public import names without reaching through vendor directories.
- Native binding selection and clear rejection of unsupported host imports.
- License inclusion, useful build errors, and debug/source-map options where supported.
- A documented way to select a supported runtime profile, if multiple profiles exist.

Illustrative API only:

```ts
bundleApp({ entry: "app.tsx", output: "generated/app.js" });
```

Acceptance test: build and run a small application outside the QuickTUI repository using only documented entry points. It should not copy QuickTUI's bundler or patch OpenTUI source text itself.

## 6. Separate application startup from the demo shell

Here, application shell means renderer startup, event routing, resize handling, and shutdown. It does not mean a command shell or a prescribed visual layout.

Extract or expose a supported application API for the reusable behavior currently obtained through `mountDemo`, `keys`, and `interceptKeys`. Keep demo-specific shortcuts and presentation in the examples. For example, a default `q` shortcut must not compete with typing into a chat composer.

Illustrative API only:

```ts
mountApp(App, { /* input and lifecycle options */ });
```

Document key consumption, paste handling, message delivery, cleanup, and ownership of the renderer. Include a minimal external-consumer example and a headless test example using the same application API.

This packaging work does not create a JavaScript security boundary. Loading less-trusted JavaScript into an existing context still requires a separate authority review.

## Application-owned follow-up work

Keep the following changes in the consumer:

- Harden the application transport request admission and wake-pipe error handling, including interrupted system calls. A failed wakeup must not leave the transport permanently busy.
- Define reconnect and uncertain-request outcomes. Do not blindly replay an operation that may already have run.
- Add subscription support to the consumer's server protocol and native transport. QuickTUI already provides the message-delivery mechanism; it does not define the consumer's events.
- Introduce a session identity and revision covering all client-visible state changes. The current transcript event sequence is not sufficient as a universal revision, since model selection can change visible state without adding a transcript event.
- Optionally combine subscriptions with a low-frequency heartbeat carrying only session identity and revision. Fetch missing events or a snapshot when needed. The heartbeat is a consistency check, not another full-state poll.
- Define cursor recovery, bounded event retention, and resynchronization after restart or a missed subscription notification.

A subtle heartbeat indicator can show connection health, but must have an understandable text/status equivalent. The consumer's operations must remain available through its CLI/protocol; UI navigation is not the only route to performing them.

## Original implementation order

1. Add endpoint failure, queue pressure, fairness, and shutdown tests; fix failures they expose.
2. Expose paste and application lifecycle APIs.
3. Publish the consumer bundler and external-application example; migrate the consumer off copied internals.
4. Implement the consumer's revision/subscription/recovery protocol independently of QuickTUI packaging.

Use in-memory and headless tests first, then a real terminal smoke test for input, paste, resizing, disconnection, and quit. Keep tests local and use disposable endpoints and temporary files.
