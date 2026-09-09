For applications without React, see [the core API](core-api.md). The `quicktui`
entry point documented here remains the compatible React adapter; it is also
available as `quicktui/react`.

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
- `onFirstLayout` runs once after initial layout but before presentation. Restore
  layout-dependent state such as viewport offsets there. QuickTUI renders again
  after the callback so the restored view appears in the first presented frame.
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
blocking native calls. Reload is deferred while queued input or a partial key/paste sequence remains.
The old runtime finishes delivering that input before export and retirement.
Incomplete pastes, including overflow discard, wait for their terminator; an
unterminated paste can keep reload pending, while native signals still allow exit.
Repeated reload requests during this wait coalesce to the first request.
Snapshots should capture the resulting draft plus any caret/selection/scroll state. Image capability state, pending-request
migration, native-triggered reload control, and broader failure tests remain work
in progress. See the reload spec for the intended full contract.

Run `zig build test-reload-consumer` for an outside-checkout build and real PTY
exercise using these public exports.


## Higher-fidelity keyboard input

```tsx
import {mountApp, HeldKeys} from "quicktui";
const held = new HeldKeys(reset => pauseSimulation(reset.reason));
let canHold = false;
mountApp(Game, {
  keyboard: {mode: "realtime"},
  onKeyboardCapabilities(caps) {
    canHold = caps.heldStateAvailable;
  },
  onInputReset(event) { held.reset(event.reason); pauseSimulation(event.reason); },
  onKey(event) {
    if (canHold) held.update(event);
    return true; // Consume gameplay input before focused-widget fallback.
  },
});
// Each simulation step: read held.has("right") and held.drainEdges().
// A press/release between frames still leaves a press edge for a one-shot jump.
```

Keyboard configuration is fixed for the native host lifetime, including reload.
The default text preset requests flags 5. The realtime preset requests all five
Kitty enhancements, flags 31: disambiguation, event types, alternate keys,
all keys as escapes, and associated text. Override individual booleans with
`disambiguate`, `events`, `alternateKeys`, `allKeysAsEscapes`, and `reportText`.
Changing flags during reload fails the candidate and reconstructs the old bundle.
The native renderer owns negotiation, focus reporting when detected, and protocol
cleanup. JS reload does not push another keyboard mode onto the terminal stack.

`onKey` receives an `AppKeyEvent`, retaining the existing `KeyEvent` fields and
adding `kind` (`press`, `repeat`, `release`), `identity`, `text`, `associatedText`,
`legacy`, `trackable`, `receivedAt`, `dispatchedAt`, and `sequenceNumber`.
The upstream `eventType` continues to represent repeat as press with `repeated`;
use `kind` for the explicit three-way distinction. Consuming with `true`,
`preventDefault()`, or `stopPropagation()` prevents subsequent delivery. Otherwise
press/repeat goes to `keypress`
and release goes to `keyrelease`, so key-up never types a second character.

Identity uses the protocol key code or named key and excludes modifiers, allowing
a letter to be released after Shift changes. It is not a hardware scan code.
`option` distinguishes Alt from `super`/Command; legacy `meta` may combine them.
Legacy uppercase/Shift metadata is a parser interpretation, not proof that a
physical modifier was held. Explicit associated text is separate from identity;
text-only protocol events do not enter the held tracker.

Times are monotonic local milliseconds, with receive time taken at the native
read boundary and dispatch time at JS normalization. A fragmented event gets the
completion read time. The sequence number is ordered within one UI runtime;
combine it with reload generation when recording across runtimes. These are not
hardware timestamps and do not measure terminal/compositor latency.

Capability callbacks distinguish requested flags from observed input. `protocol`,
`releases`, `focus`, and `modifierEvents` begin unknown. `heldStateAvailable` becomes
true only after observing a Kitty release. This is evidence of that path, not a
guarantee that every OS shortcut, modifier, or multiplexer forwards all events.
In particular, an arrow release does not prove that letters have releases.
`trackable` identifies a protocol key with an identity, not a per-key capability
promise. There is no per-key capability map or interactive calibration API yet.
The game uses explicit tap-to-step controls before release support is observed.
Legacy input never gets synthetic key releases or a guessed hold timeout.

`HeldKeys` ignores duplicate presses, unknown releases, and orphan repeats after
reset. It exposes a held-identity set, logical-name queries, and ordered edges.
Both held state and the edge queue are bounded; overflow clears state and invokes
the reset callback. Wire that callback to pause the application.

Input resets report startup, runtime reload, terminal focus loss when forwarded,
SIGCONT/resume, detected parser overflow, backend endpoint closure, and shutdown.
Reset notifications tell the application to clear its tracker; they do not clear
consumer-owned state automatically. Do not restore held keys from application
JSON. Require fresh presses to resume. Unsupported focus reporting remains an
observable limitation, and uncatchable termination cannot restore terminal modes.

See `quicktui --keyboard`, `quicktui --game`, and
[the compatibility record](keyboard-compatibility.md). The examples target 60 Hz;
local timing is displayed, but no physical-key latency guarantee has been measured.

### Component keyboard subscriptions

`useKeyboardEvents` subscribes for the lifetime of a mounted component:

```tsx
import React, {useState} from "react";
import {mountApp, useKeyboardEvents} from "quicktui";

function KeyMonitor({active = true}) {
  const [last, setLast] = useState("Press a key");
  useKeyboardEvents(event => {
    setLast(`${event.name}: ${event.kind}`);
    // No return value: the focused widget can still handle this event.
  }, {
    enabled: active,
    realtime: true,
    onReset: event => setLast(`Input reset: ${event.reason}`),
  });
  return <text>{last}</text>;
}

mountApp(KeyMonitor, {keyboard: {mode: "realtime"}});
```

The app still requests `keyboard: {mode: "realtime"}` at `mountApp` to ask the
terminal for releases. A component's `realtime` option only filters its
subscription; it never changes terminal modes. The default, `realtime: false`,
receives presses and repeats like ordinary widget keypress handling. Setting it
to true also receives releases when available. `enabled` defaults to true and can
change at runtime, as can `realtime` and the callbacks. Disabling or unmounting
removes the subscription. Components owning held state should clear it when they
become inactive as well as in `onReset`.

Routing order is app `onKey`, enabled component subscriptions in registration
order, then existing widget routing. Returning true, calling `preventDefault`,
or calling `stopPropagation` stops subsequent delivery. Hook callbacks should
return nothing when observing. Hooks are global subscriptions, not automatically
focus-scoped; use `enabled: focused` for a focused component. Releases go only to
the release channel and never to widget keypress handlers. Repeats remain normal
keypress events for text editing. Mounting a hook does not synthesize events that
the terminal did not send. The game and keyboard diagnostic use this public hook.

App-level keyboard options are construction-only. Passing different options on a
full runtime reload is rejected; changing a component hook's filter is allowed.
An app-level `onKey` that consumes everything also prevents these hooks from
receiving events. Startup reset happens before components mount, so hooks should
initialize with empty held state rather than wait for that initial notification.
