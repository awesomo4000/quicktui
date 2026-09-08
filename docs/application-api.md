# Building an application with QuickTUI

The [independent consumer](../examples/consumer/) is a complete small application.
Normal builds use its generated JS file; rebundling TSX requires Bun.

## Bundling

```sh
bun path/to/quicktui/scripts/bundle-app.ts app.tsx generated/app.js
```

Or call the build-time API from a Bun script:

```ts
import {bundleApp} from "./quicktui/scripts/bundle-app";
await bundleApp({entry:"app.tsx",output:"generated/app.js",sourcemap:"external"});
```

Entry and output paths resolve against the caller's working directory. QuickTUI
resolves its own vendored libraries against its installation directory. It installs
bootstrap before evaluating the application and includes upstream license notices.

Supported imports include `react`, `react/jsx-runtime`, `quicktui`,
`quicktui/widgets`, and `quicktui/testing`. `@opentui/core` resolves to the same
selected widget catalogue. The current build has one fixed native registry;
there is no consumer-selectable permission or native-binding profile yet.
Unsupported Node/Bun host imports fail the build. Internal OpenTUI filesystem
stubs remain for paths excluded from the supported host; consumer `fs` imports
are rejected. This is compatibility checking, not a security boundary.

Bundles are unminified. Optional external source maps include original source
content and file locations, so review them before publishing. QuickJS currently
reports generated positions under `examples.js`; it does not apply those maps
to exception stacks. The maps are for external debugging tools.

## Startup and input

```tsx
import React from "react";
import {mountApp, quit} from "quicktui";

mountApp(App, {
  onKey(key) {
    if (key.ctrl && key.name === "c") { quit(); return true; }
  },
  onPaste(text) { /* insert literal text; do not execute or submit it */ },
  onPasteRejected() { /* report a paste larger than 1 MiB */ },
  onMessage(message) { /* process an application-defined string */ },
  onDisconnect(reason) { /* show a disconnected state */ },
});
```

`mountApp` owns one React root and borrows the host renderer for one runtime invocation.
It returns `quit()` and `snapshot()`. A second mount is rejected. It installs no
Q or Ctrl+C shortcut; the application chooses those. A key callback runs before
the focused widget. Returning true or calling `key.preventDefault()` consumes
it; otherwise the focused widget receives the key event. Mouse routing, selection,
resize, dirty rendering, timers, and React unmount are shared with the demos.
`mountDemo` retains legacy shortcuts for existing examples.

Paste is delivered separately as literal UTF-8 text when `onPaste` is supplied.
Otherwise a focused widget can receive the paste event. It is never submitted as
a series of key commands. The limit is 1 MiB of payload bytes, including across
fragmented reads. An oversized paste is discarded through its closing delimiter;
its suffix does not become keyboard input. The rejection callback runs once when
the closing delimiter arrives. An unfinished paste is discarded at shutdown.
Empty input chunks emit nothing. Terminal input without paste framing cannot be
distinguished from ordinary typing.

This API receives user input. It does not grant programmatic clipboard reads or
image paste. Separate host-controlled clipboard capabilities are still planned.
The existing OSC 52 copy binding and other low-level native operations remain in
the trusted runtime; importing fewer functions does not isolate untrusted code.

## Native messages

Use the exported Zig module and `runApp(source, .{ .endpoint = &endpoint })`.
For tests use `.headless = true`. Without an endpoint, omit that option.
The application owns worker startup, cancellation, joining, and queue storage.
The host never closes the endpoint descriptor or destroys its context.

`sendMessage(text)` returns `accepted`, `rejected`, or `closed` synchronously.
There is no automatic retry. Messages are UTF-8 strings limited to 4096 bytes.
Accepted sends must copy their bytes before returning; rejected sends must retain
nothing. The existing `__host.postMessage` boolean API remains compatible.
The consumer's transport documents queue capacities and ordering. A rejection may
mean temporary queue pressure or an application-specific admission decision.

Native callback outcomes:

| Callback | Result |
| --- | --- |
| send | 1 accepted; 0 rejected; -1 closed; -2 failed |
| receive | nonnegative byte count; -1 empty; -2 closed after draining; -3 failed |

Callbacks run on the UI thread and must not block. `wake_fd` must remain readable
while replies are queued. The receive callback consumes wake notifications.
Do not close or reuse the read descriptor while the host runs. Close the producer
end to signal hangup, or return an explicit closed result after draining replies.

Hangup removes the descriptor from polling and drains queued replies in bounded
batches before reporting closure. Sends are rejected as closed during that drain.
Descriptor error or invalidity disconnects immediately; queued replies may be
unrecoverable. The host calls `onDisconnect` once with `closed`, `send-error`,
`receive-error`, `descriptor-error`, or `invalid-descriptor`, and leaves the UI
open. It stops endpoint callbacks after closure. Reconnect, pending-request
outcomes, replay policy, and resynchronization belong to the application.

The host services at most 32 messages and 128 promise jobs per turn, alongside
timers and rendering. Input and resize get opportunities between turns. This is
a scheduling bound, not preemption of a slow JavaScript callback. Coalescing
replaceable frames is an explicit transport choice, not a host policy for events.

`takeBuffer(id)` copies an optional native binary payload into an ArrayBuffer,
up to 4 MiB, then releases the borrow. Missing IDs return null. It is available
only when the endpoint provides both binary callbacks. It is not a clipboard API.

After `runApp` returns, signal cancellation and wake blocked worker waits, join
workers, then release descriptors and queue storage. A worker waiting for queue
space must also wake when cancelled. Never join while holding its queue mutex.
Shutdown does not promise to finish accepted requests. The application must define
those outcomes. React effects should return cleanup functions for subscriptions
and timers; the host unmounts React before destroying native rendering resources.

## Tests

`quicktui/testing` exports `testApp(async driver => ...)`. Under headless execution
it registers the test callback; under interactive execution it does nothing.
The driver supplies `input(text)`, `resize(width,height)`, and `snapshot()`.
Input and resize flush scheduled UI work. Use the same `mountApp` as production.

```sh
zig build test -Doptimize=ReleaseSmall
zig build test-paste test-bundler
zig build test-endpoint-terminal -Doptimize=ReleaseSmall
zig build test-consumer
```

The extra tests require Bun and/or Python. They use disposable pipes, PTYs, and
temporary directories. Tests cover closed and faulty endpoints, hangup with queued
messages, sending during hangup, message flooding alongside other event sources,
full-queue shutdown, repeated teardown, paste fragmentation and overflow, and an
application built from outside this repository.


### Renderer lifetime

The native host owns the terminal renderer. `mountApp` borrows it for the life of
one UI runtime. UI shutdown unmounts React and disposes JS callbacks and wrappers;
the renderer and its last complete frame remain alive until final host shutdown.
The host then destroys the renderer and restores the terminal.

The normal run functions still run one UI runtime per call. The experimental
`runReloadable` entry point drives example 06b. See GUIDE.md for its controls,
snapshot contract, and current limitations.
It does not introduce a sandbox around the existing trusted native bridge.


## Opt-in runtime replacement

[The reload consumer](../examples/reload-consumer/) builds independently of the demos.
Enable the experimental lifecycle in the native caller:

```zig
try quicktui.runApp(@embedFile("app.js"), .{ .reload = true, .endpoint = endpoint });
```

Omit `endpoint` when no worker is needed. It stays owned by the caller and remains
alive across replacements. `.reload` defaults to false.

```tsx
import {mountApp, getReloadState, getReloadInfo, requestReload} from "quicktui";

const state = getReloadState({version: 1, count: 0});
// Validate snapshot shape/version before mounting; the generic type is not validation.
mountApp(App, {
  exportState: () => state,
  onReloadError: notice => showStatus(notice),
  onKey(key) {
    if (key.ctrl && key.name === "r") { requestReload(); return true; }
  },
});
```

- `requestReload()` reuses the last successfully presented bundle.
- `requestReload(bundledSource)` supplies a complete trusted application bundle,
  not a component fragment. The host copies it before returning, capped at 16 MiB.
- `exportState` runs after regular dispatch stops. It must synchronously return
  JSON-serializable data, capped at 1 MiB after serialization. It must not send
  backend requests. Missing/failed export aborts replacement and invokes
  `onReloadError` if provided. A missing callback leaves reporting to the application.
- `getReloadState(fallback)` reads the restored JSON or returns the fallback on
  the initial mount or a null snapshot. Validate and migrate application versions.
- `getReloadInfo()` returns `{enabled, generation, notice}`. Failed candidate
  recovery is reported in `notice` when the previous bundle is reconstructed.
- Calling `requestReload` without native opt-in throws. Normal app startup,
  endpoint behavior, and demo shortcuts remain unchanged.

Replacement disposes the old runtime, prepares the candidate without the normal
frame presenter writing to the terminal, then presents its first completed frame.
Only explicitly exported data survives. Candidate failure reconstructs the last
successful bundle with the snapshot; it does not resurrect the old heap.
Endpoint replies remain queued; no backend operations are canceled or replayed.
Do not start backend work during candidate mount: sends are rejected until activation.
A later timer or user event can start work once the new UI is active.

This remains an experimental trusted-code API. The normal presenter is gated,
but arbitrary direct native bridge calls are not restricted. Preparation has a
two-second JS deadline; cleanup has a 500 ms deadline, neither of which interrupts
blocking native calls. Input remaining in the triggering batch is discarded;
partial paste/parser state is not migrated. Image capability state, pending-request
migration, native-triggered reload control, and broader failure tests remain work
in progress. See the reload spec for the intended full contract.

Run `zig build test-reload-consumer` for an outside-checkout build and real PTY
exercise using these public exports.
