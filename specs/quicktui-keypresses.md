# QuickTUI keyboard input for real-time applications

Date: 09/09/2026
Status: proposed requirements for the QuickTUI team

## Goal

An application should be able to implement a keyboard-controlled platformer
inside QuickTUI: hold a direction to move, press jump while moving, release jump
early for a short hop, and release direction to stop. Movement must not depend
on OS key-repeat delay or on an LLM/backend round trip.

This is an input contract, not a request for a game engine. It must also work for
editors, interactive diagrams, and other applications needing accurate key state.
Use the existing OpenTUI parser and native renderer where possible.

## Current implementation findings

These findings describe the locally inspected source, not an upstream guarantee:

- OpenTUI parses `press`, `repeat`, and `release` and exposes `eventType` on
  `KeyEvent`. Its regular key handler distinguishes `keypress` and `keyrelease`.
- OpenTUI's TypeScript keyboard options include `events`, `allKeysAsEscapes`,
  and `reportText`. They default to false. Disambiguation and alternate-key
  information default to true.
- Native terminal options default to keyboard flags `0b00101`. That does not
  request repeat/release event reporting or all-keys-as-escapes reporting.
- QuickTUI's persistent application host calls native `setupTerminal` without
  exposing an application keyboard configuration in the path we inspected.
- QuickTUI's `mountApp` passes a parsed `KeyEvent` through `onKey`, retaining its
  event type. Its fallback emitter currently emits `keypress` for every key
  event. That fallback must distinguish releases before richer input is enabled.
- The consumer application’s injected CSI-u release test proves parsing and application handling.
  It does not prove that a physical keyboard, terminal, and multiplexer forward
  releases end to end.

Relevant source locations, relative to the QuickTUI checkout:

- `src/app_host.c`: persistent renderer initialization and terminal ownership.
- `js/platform/demo.tsx`: `mountApp`, input parsing and callback dispatch.
- `vendor/opentui/packages/core/src/renderer.ts`: keyboard configuration flags.
- `vendor/opentui/packages/core/src/lib/KeyHandler.ts`: event representation.
- `vendor/opentui/packages/core/src/lib/parse.keypress.ts`: parsed key fields.
- `vendor/opentui/packages/native/src/terminal.zig`: native protocol defaults.

## Required consumer API

Expose a supported opt-in real-time keyboard mode through the public application
API. Do not require consumers to call private FFI symbols, emit escape sequences,
or import a demo implementation. The exact API names are open; this is illustrative:

```ts
mountApp(Game, {
  keyboard: { mode: "realtime" },
  onKey(event) { /* press, repeat, release */ },
  onInputReset(event) { /* stop movement, clear held state */ },
  onKeyboardCapabilities(capabilities) { /* full or degraded controls */ },
});
```

The public API must also support explicitly selecting protocol enhancements for
consumers that do not want the preset. Define whether options take effect at
initial startup only or can change at runtime. The persistent native host owns
negotiation and cleanup, including across JS reloads.

Real-time mode should request event types, all-key reporting, and unambiguous key
identification. Support associated text and alternate/base-layout information so
that enabling game controls does not break text fields. Choose and document the
precise flag combination after reviewing the existing native implementation.

## Event semantics

Each normalized event must preserve:

- Kind: press, repeat, or release. A release is never a second press.
- Logical key name and the strongest stable key identity the protocol provides.
- Modifier snapshot: Shift, Control, Alt/Option, Super/Command, and other
  supported modifiers. Distinguish Alt from Super rather than conflating both
  under a single ambiguous meta flag.
- Associated text separately from key identity, when available.
- Monotonic local receive time and ordered sequence number, or equivalent
  metadata sufficient for replay and latency measurement.
- Source/protocol and any ambiguity needed to interpret legacy input honestly.

Do not promise hardware scan codes, exact physical-key identity, or original
hardware timestamps when the terminal does not supply them. Record what arrived,
not an invented physical event. Uppercase text alone is not proof of held Shift.

State tracking must support overlapping keys. For example, right remains held
while Space is pressed and released. Releasing Shift while a letter is held must
not prevent matching that letter's eventual release. Report modifier-only events
where the negotiated protocol and host support them.

Provide a reusable held-key tracker, or a documented reference implementation:

- Press adds the key; repeat keeps it held; release removes it.
- Repeated press reports for an already held key do not trigger another rising
  edge in the tracker. Preserve the original event for consumers that need it.
- Unknown releases are harmless, including after input reset.
- Consumers can get both the held set and ordered edges since the last update.
  A quick press/release between render frames must still trigger jump once.
- Text insertion and shortcuts run on appropriate press/repeat events, never on
  release. Repeats must not repeatedly trigger a one-shot action such as jump.

No synthetic release after an arbitrary timeout: that would stop a legitimately
held key. Legacy press-only input cannot provide trustworthy held-key state.

## Focus, interruption, and reload

Stuck movement is a correctness failure. Define an explicit input-reset event
with a reason and clear held keys on observable loss of input continuity:

- Terminal focus loss, when reported.
- Suspension/resume or terminal connection loss.
- Input queue overflow or detected loss of events.
- Runtime replacement if continuity cannot be preserved safely.

Request focus reporting where supported. If a terminal or multiplexer does not
forward focus loss, expose that limitation; do not claim stuck-key prevention is
complete in that environment. Applications should pause when continuity is lost
and require fresh presses after resuming.

For persistent JS reload, choose one documented policy: transfer a host-owned
held-state snapshot with ordered buffered events, or issue a reset before the new
runtime accepts input. Do not restore stale held keys from arbitrary application
JSON. Do not replay one-shot actions or let release events become text. A failed
candidate reload must leave keyboard protocol ownership and routing consistent.

Balance terminal protocol push/pop operations. Normal exit and handled failures
must restore the previous mode; repeated reloads must not accumulate stack
entries. Abrupt process termination cannot guarantee cleanup and must be stated
as a limitation. No changes to the user's terminal configuration are required.

## Capability reporting and fallback

Report requested settings separately from negotiated/observed support. Suggested
fields include protocol, event-type support, modifier-event support, focus-event
support, and whether a reliable held-state tracker is available. Use unknown
where support has not been established. A successful write of an enable sequence
is not proof that releases will arrive.

Unsupported terminals must remain usable for text applications. A game may offer
explicit tap-to-step controls or decline continuous controls with an explanation.
Never silently advertise full real-time support while estimating key releases.
OS shortcuts, multiplexer shortcuts, hardware rollover, and unsupported protocol
features remain outside QuickTUI's control.

## Dispatch and responsiveness

- Dispatch input locally on the UI thread without waiting for the consumer application, an LLM,
  network polling, or a long-running worker response.
- Update held state before the next simulation step. A simulation can use a
  fixed timestep and inspect held keys; rendering need not run once per event.
- Preserve press/release order across split reads, multiple events per read,
  native messages, resize, and runtime replacement.
- Bound queues. Do not silently discard releases under load. If events are lost,
  emit an explicit reset and diagnostic instead of leaving a key held forever.
- Event consumption must prevent duplicate application actions. `onKey` and
  fallback event subscribers need a documented routing/consumption contract.
- Bracketed paste remains text input, not hundreds of gameplay key presses.

Target a responsive 60 Hz example on a documented local reference machine. For
ordinary load, local input ingestion to callback dispatch should have p95 under
one 16.7 ms frame, with p99 and worst-case also reported. Treat this as a measured
target, not a hard real-time guarantee. Distinguish local dispatch latency from
physical-key-to-screen latency; the latter includes the terminal and compositor.

## Acceptance tests

### Deterministic and in-memory

1. Decode press/repeat/release, modifier combinations, ordinary characters,
   arrows, Space, Escape, function keys, and available modifier-only events.
2. Split each representative protocol sequence at every byte boundary, including
   UTF-8 boundaries. Also deliver several events in one read. Verify order and
   event identity are unchanged.
3. Hold right, press jump, release jump, then release right. Verify movement
   persists until right release and jump has exactly one rising edge.
4. Press and release jump between frames. Verify the edge is not lost.
5. Hold two opposing directions and release one. The tracker preserves the
   remaining key; the application chooses its movement policy.
6. Change modifier state before releasing a letter. Verify no stuck key.
7. Exercise duplicate presses, repeats, unknown releases, focus reset, overflow
   reset, and runtime replacement. Verify no duplicate actions or retained keys.
8. Verify consumed events are not delivered twice and fallback subscribers
   receive `keyrelease` for releases, not `keypress`.
9. Verify text input, paste, Alt combinations, and available international-layout
   key/text distinctions still work. Releases must never insert characters.
10. Assert protocol setup/teardown balance across startup, exit, failed startup,
    successful reload, and failed reload.

### PTY and physical-key verification

Provide a diagnostic example showing recent events, modifiers, protocol status,
held keys, reset reason, and latency statistics. Keep this separate from the game
so failures can be diagnosed without interpreting animation.

Provide a small platformer or moving-box example with left/right movement, jump,
and simultaneous controls. Hold movement for several seconds, jump while moving,
release in different orders, change focus, and reload while a direction is held.
Use actual key-up events rather than OS repeat frequency to stop movement.

Run a direct supporting-terminal test and the same test through Herdr. Include a
legacy/unsupported terminal case. Record terminal, OS, multiplexer versions,
requested flags, observed event support, and input/dispatch measurements.
Injected PTY sequences test the app path; actual human key transitions test the
terminal/multiplexer path. Report those results separately. Do not infer physical
release support from a scripted key-injection API that cannot send releases.

Keep demonstration actions programmatically callable for automation: the game
controller's input/reset operations and diagnostic output must not be mouse-only.
Provide textual state for accessibility and headless verification, not only a
visual position on screen. This does not imply an LLM needs raw keyboard access.

## Scope and completion

Required deliverables: public configuration, correct event routing, capability
reporting, held-state/reset behavior, diagnostic and game examples, automated
tests, and a recorded direct-terminal/Herdr compatibility result.

No broad JS authority, filesystem access, the consumer application tool capabilities, gamepad input,
or game engine is required. This belongs to QuickTUI's trusted local input layer.
the consumer application should only need to select the supported mode and subscribe through the
public API. If Herdr blocks required events, document the exact missing behavior
for its maintainers rather than declaring the end-to-end feature complete.


## Follow-up: printable releases through Herdr

- [ ] Retest physical WASD press/repeat/release through a separate Herdr 0.9.0
  session. Keep arrows available in the game meanwhile.
- [ ] Investigate why the tested Herdr 0.8.2 path forwards printable keys as
  legacy text without releases, while arrows work and direct Ghostty 1.3.1
  delivers letter releases. Issue #1746 was marked fixed in v0.8.0, so the
  original fix alone does not explain our observation.
- [ ] Check associated-text encoding and held-key routing as possible causes;
  do not describe either as confirmed without a reproducer isolating the path.

Upstream: https://github.com/herdrdev/herdr/issues/1746
Diagnostic notes: `x/keypress-herdr-notes.md` (local, ignored).
No server restart is needed for this follow-up to remain recorded.
