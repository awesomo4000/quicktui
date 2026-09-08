# QuickTUI persistent host and flicker-free UI reload

Date: 09/07/2026

Status: proposed API and behavior, not an existing QuickTUI guarantee.

## Goal

Replace an application's JavaScript runtime inside a running terminal UI without
flashing the normal terminal screen, clearing the display, restarting the native
process, or disconnecting the application's backend transport.

The user should continue seeing the last complete frame until the replacement
UI has produced its first complete frame. Ordinary changes should appear as a
single visual update. An unchanged UI should produce no visible flash.

This is initially a trusted developer feature. It does not introduce JavaScript
sandboxing, mobile code, or model-controlled installation. The consumer application’s capability
security remains in its Racket backend.

## Current integration and why it flickers

The consumer application currently uses QuickTUI's `runWithMessages`. That call owns the entire
application lifetime: terminal setup, JavaScript runtime/context creation,
rendering, shutdown, terminal restoration, and runtime destruction.

The consumer application’s development host keeps its socket worker alive around repeated calls to
`runWithMessages`. It remembers one configured bundle path. A watcher builds
TSX and atomically publishes successful JavaScript bundles. The native host
detects a changed bundle and sends a reload notification. The old UI exports a
JSON snapshot and calls the host quit function. The development host then starts
another application run with the new bundle and snapshot.

This creates fresh JavaScript runtimes and preserves application data, but each
run leaves and re-enters the alternate screen. Terminal restoration and renderer
startup are visible as a flash. Calling quit is doing more work than reload
actually requires.

## Ownership model

Separate the persistent terminal host from the replaceable UI generation.

| Persistent until application exit | Replaced on UI reload |
| --- | --- |
| Terminal modes, alternate screen, terminal identity | JavaScript runtime and context |
| Input source, resize handling, process signal policy | React tree and JavaScript listeners |
| Application-owned message endpoint | UI timers, promises, and module globals |
| Last presented frame and display-diff baseline | Generation-owned native renderables and buffers |
| Native reload control and diagnostics | UI event handlers and subscriptions |

The precise renderer split is an implementation choice. A persistent renderer
may outlive its renderable tree, or a candidate renderer may draw off-screen and
hand its frame to a persistent presenter. Either way, terminal ownership must
not be destroyed with the JavaScript context.

Retaining the last frame means retaining pixels/cells or another safe display
representation. It must not require invoking renderables or callbacks belonging
to a destroyed generation.

## Required reload lifecycle

```text
running generation A
    -> quiesce A
    -> export state
    -> prepare generation B without terminal output
    -> restore state and render B off-screen
    -> present B atomically
    -> activate B and retire A
```

The preferred sequence retains A until B is ready so failure can resume A.
If QuickTUI cannot keep two generations alive simultaneously, a sequential
implementation is acceptable as a documented first version: retain A's frame,
dispose A, initialize B, and reconstruct A from its bundle and snapshot on
failure. The visible terminal must remain owned and unchanged throughout.

### 1. Quiesce the old generation

- Stop accepting UI actions for the old generation.
- Pause its timers, promise-job execution, event delivery, and rendering before
  taking the snapshot.
- Allow the state-export hook to run under an explicit quiesced policy.
- Reject new application transport sends from that generation after quiescence.
  State export must use a separate host facility, not ordinary backend requests.
- Do not cancel or replay requests already accepted by the native transport.

An observed race motivates this ordering. QuickTUI's current step calls message
delivery, then tick, promise jobs, and frame. A reload callback can save a
snapshot and request quit during message delivery, yet a subsequent tick can
still submit a poll. The new UI restores a snapshot that does not include that
request and sees unexpected transport contention. Reload must be a lifecycle
barrier, not just a flag checked at the end of a frame.

### 2. Export application state

Provide a hook for an application-owned, versioned, data-only snapshot. The consumer application’s
snapshot includes its draft, caret, transcript/event cursor, selected model,
picker state, scroll position, and pending request IDs.

The host retains the snapshot outside the old JS runtime. Bound its byte size
and report serialization/export failures without destroying the working UI.
Do not carry JS objects, closures, pointers, or native handles across runtimes.

QuickTUI need not understand conversations, models, or requests. It only needs a
documented serialization and restoration contract. The consumer application currently uses JSON;
the API can accept opaque bytes if that makes ownership clearer.

### 3. Prepare the replacement

- Create a fresh JS runtime/context with the configured host bindings.
- Evaluate the trusted bundle and mount the application without terminal output.
- Supply the snapshot through an explicit restore facility.
- Keep normal input and backend-message delivery paused until activation.
- Prevent candidate initialization from sending backend operations. Candidate
  failure must not leave an externally visible action behind.
- Render the initial frame into an off-screen target of the current dimensions.
- Declare readiness only after initialization, restoration, and initial layout
  have succeeded. Bound synchronous evaluation and asynchronous readiness waits.

The candidate must not reset terminal modes, request an alternate screen, emit
capability probes, change the cursor, or write diagnostics directly over the
existing UI. Initial capability discovery belongs to the persistent host.

### 4. Present and activate

- Present one complete replacement frame against the persistent display state.
- Do not exit/re-enter the alternate screen or clear to a blank frame first.
- Use synchronized terminal output when supported. Maintain the existing
  renderer's best available complete-frame behavior on other terminals.
- Activate the new generation's input, timers, and message handlers.
- Release all resources owned by the retired generation.

The last displayed frame is a presentation fallback, not continuing execution
of the old application.

## Messages and input during reload

### Backend messages

The endpoint remains application-owned and alive. It must never be closed just
to reload the UI. Document whether messages remain in the endpoint queue or in
a bounded host queue while delivery is paused. Preserve order and existing
backpressure semantics. Never silently drop replies or replay requests.

An accepted request may complete during reload. Its reply must be delivered to
the new generation exactly once within the local host/endpoint delivery
contract. This does not claim distributed exactly-once execution. The consumer application is
responsible for retaining pending IDs and interpreting uncertain remote results.

### Keyboard and paste

Choose and document a bounded input policy during the swap. Prefer retaining
complete input events for delivery to the activated generation. Do not split
bracketed paste across generations or accidentally submit pasted newlines.
If input must be discarded, make that explicit rather than claiming transparent
draft preservation.

Keep native application-exit controls responsive throughout reload. They must
not depend on the candidate's JavaScript functioning correctly.

### Resize

Retain the latest terminal dimensions while reload is in progress. If the size
changes during preparation, lay out the replacement at the latest size before
presentation. Do not reveal a stale-size frame or invoke the old JS resize
handler after its generation has been retired.

## Failure and recovery

| Failure | Required behavior |
| --- | --- |
| Bundler fails before publishing | Running UI is unchanged; watcher reports diagnostics |
| Snapshot export fails or exceeds limit | Abort reload and resume current UI |
| Candidate syntax/evaluation/mount/restore fails | Keep previous frame; resume old generation or reconstruct it |
| Candidate readiness times out | Interrupt candidate, release its resources, recover old UI |
| Reconstructing the old UI also fails | Native-owned error/recovery path; do not spin retrying indefinitely |
| Endpoint disconnects during reload | Preserve disconnect state and notify the activated UI without killing the terminal host |
| User exits during reload | Cancel preparation, clean up all generations, restore terminal once |

Keep diagnostics outside the replaceable context. Applications should be able
to show them after recovery or retrieve them through a developer control API.
Do not print an exception over the retained frame during preparation.

Only promote a bundle to the last-known-good version after it reaches the
defined ready/presented state. Retaining a bundle does not undo external effects
from an application that later fails; post-activation crash recovery is a
separate policy and must not promise lossless rollback.

## Suggested public API shape

Illustrative names only; the QuickTUI maintainer should choose the final API.

```zig
var host = try qt.AppHost.init(options);
defer host.deinit();

try host.mount(initial_bundle, initial_state);
// The host event loop receives a native reload request:
try host.replaceUi(next_bundle);
```

Useful concepts to expose:

- Persistent host creation/run/exit.
- Mount and replace operations with explicit bundle-buffer ownership.
- State-export and state-restore hooks.
- Preparation/readiness success and failure notifications.
- A native reload request that wakes the host event loop safely.
- Host-owned diagnostics and generation IDs for debugging stale callbacks.
- Explicit final shutdown, distinct from unmounting a UI generation.

Do not require an application to copy QuickTUI's C host or patch internal
renderer code to use this. Preserve `runWithMessages` as a convenience wrapper
over the persistent host if practical.

## Resource isolation between generations

Review native registries and cleanup functions that currently assume one
runtime owns everything. In particular, context teardown, FFI handle cleanup,
buffer-view cleanup, and renderer destruction must not invalidate a candidate
or persistent presenter belonging to another lifetime.

If native handles are process-global, either tag them by generation or provide
another ownership scheme that prevents cross-generation use and cleanup.
Delayed callbacks from retired generations must not execute. JavaScript GC
alone does not establish ownership of native resources.

Two simultaneous runtimes are an optimization for rollback, not a prerequisite
for the first version. A sequential swap with a persistent display is preferable
to unsafe overlap of global native registries.

## Division of responsibilities

QuickTUI owns terminal continuity, runtime/renderable lifecycle, event pausing,
safe frame presentation, and the supported host API.

The consumer application owns bundle watching/building, selecting the trusted bundle, the contents
of its UI snapshot, transport request bookkeeping, and its backend session.
Reload remains unavailable to the consumer application’s ordinary conversational tool namespace.

A future developer control socket can request reload of the configured bundle.
An arbitrary bundle path supplied by an untrusted message is not required.
Filesystem watching itself does not need to become a QuickTUI feature.

## Acceptance tests

### In-memory lifecycle tests

1. Reload repeatedly; each generation starts with clean globals and module state.
2. Retain a Unicode/multiline draft, caret, scroll position, and application data.
3. Assert retired timers, listeners, promise jobs, and native handles are cleaned
   up; allocation/descriptor counts do not grow across repeated swaps.
4. Assert no send occurs after quiescence, including the remaining tick/jobs in
   the frame that received the reload request.
5. Complete an outstanding request during reload; deliver its reply once and
   preserve subsequent request admission without a stuck busy state.
6. Exercise full message queues and bounded input buffering during slow reload.
7. Inject syntax, mount, restore, snapshot-size, and readiness-timeout failures.
8. Resize during preparation and verify the first replacement frame dimensions.
9. Exit during every reload phase and verify cleanup completes.

### Terminal-output tests

Capture actual terminal output using a disposable PTY. After initial startup
and before final application exit, a reload must not emit alternate-screen exit
or entry, full terminal reset, or an intentional blank intermediate frame.
Test both unchanged and visibly changed UI bundles.

Verify terminal modes and cursor handling are restored on final exit, including
failure paths. A final terminal restoration is required; suppressing all cleanup
is not an acceptable way to eliminate flicker.

### Interactive smoke test

Run an application, type an unsent draft, and save a color/layout change. The
same terminal session should show the new UI without a flash or missing draft.
Repeat with a deliberately broken bundle, then fix it. Repeat with a backend
request in flight and with terminal resizing.

All test files and sockets should be disposable fixtures under `/tmp` or a
platform-appropriate temporary directory. No model calls or external services
are required for this test suite.

## Non-goals for this change

- JavaScript ocap sandboxing or model-authored extension policy.
- Conversation/database persistence.
- Backend session discovery and switching.
- New visual widgets, commands, or connection indicators.
- Replacing the bundler or implementing module-level hot replacement.

The desired first result is simply a clean, supported whole-UI replacement
inside a persistent terminal host.
