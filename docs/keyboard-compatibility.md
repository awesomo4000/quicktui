# Keyboard verification record

Date: 09/09/2026

## Automated

- macOS development environment, Zig 0.16.0, Bun 1.3.14.
- `zig build test-keyboard`: deterministic parser/tracker/physics tests and
  disposable PTY negotiation/routing/cleanup tests.
- The supporting PTY fixture identifies itself as Kitty and acknowledges focus
  reporting. The test asserts a flags-31 push, one matching pop on exit, and
  injected repeat/release/focus input. This is a simulated terminal response,
  not a claim about an installed Kitty version.
- The legacy fixture supplies no supporting response and remains usable without
  advertising releases or reliable held state.
- Both game and diagnostic have headless checks in `zig build test`.
- Full-course physics playback reaches the exit; short-hop, wall and pit cases pass.

## Observed terminal behavior

Physical testing through Herdr 0.8.2 in Ghostty found partial forwarding:
arrows and modifiers produce Kitty releases, but ordinary letters arrive as
legacy text without releases. Continuous WASD controls are therefore not usable
on that tested path.

Direct Ghostty 1.3.1 delivered Kitty A/D/W press and release events in a separate
window using its AppleScript key-event API. The diagnostic showed matching
identities and cleared held state on release. This verifies Ghostty encoding and
QuickTUI decoding for those events; it is not a complete physical-keyboard or
IME compatibility test.

Inspection of Herdr v0.8.2 found two candidate causes: `encode_terminal_key` in
`src/input/encode.rs` returns generated text before considering the requested
Kitty flags, and `InputLeaseTable::complete_press` in `src/app/input/lease.rs`
skips tracking keys with generated text. These paths warrant investigation, but neither has been isolated as the cause of
this run. Upstream [issue #1746](https://github.com/herdrdev/herdr/issues/1746) was
marked fixed in v0.8.0. Retesting a separate 0.9.0 session is still pending; do not
restart a working session merely to perform this check.

No physical p95 latency measurement is recorded yet. The diagnostic reports a rolling
256-event local read-to-dispatch p95/p99/max, which excludes OS and display latency.

## Remaining checks

Run `quicktui --keyboard` directly and through Herdr. Test A/D/W individually,
including each release, then overlapping movement and jump. Hold right, press/release
Space while still holding right, then release right. Repeat while changing Shift,
switching focus, and resuming the terminal. Record exact terminal/multiplexer
versions and whether releases, modifier events and focus loss reach the callback.
Then try `quicktui --game`. Press R to reset and Ctrl+C to exit.

The broader spec remains proposed until physical forwarding and the remaining
pathological/reload protocol cases are verified. A successful mode write or
scripted injection is not a substitute for that check.
