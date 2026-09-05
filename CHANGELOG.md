# Changelog

## Unreleased - 09/05/2026

- Preserve the dragon demo as example 01 and add a separate mouse playground via `--mouse`.
- Connect native hit testing to React hover, button, drag, and wheel handlers with press-target capture.
- Test split mouse reports, all three buttons, wheel input, release outside the target, resizing, and terminal cleanup.

- Send sprite frames as raw RGBA pixels to avoid the blank PNG sprite path through Herdr.
- Add play/pause and single-frame controls for the wing-cycle preview.

- Preview all eight dragon wing poses at 8 FPS on the right side of the demo, with predecoded frames and timer cleanup.

- Keep direct and tmux images above opaque cell backgrounds.
- Preserve graphics across tmux redraws using virtual placements and Unicode placeholders; test counter updates and resizing.
- Keep the dragon picture in `assets/dragon.jpg` with its source attribution.
- Embed the vendored dragon picture and decode it natively for the graphics demo.
- Forward terminal identity before probing so tmux receives properly wrapped graphics queries.
- Correct terminal-response parsing and gate pixel images on the matching successful graphics reply.
- Add a native RGBA image demo with block fallback, plus probe and tmux pane-title regression tests.

- Add an interactive React/OpenTUI counter with keyboard controls, resize handling, and native Unicode text.
- Adapt the existing React host configuration, component behavior, and render traversal to QuickJS.
- Generate 63 native wrappers with signature checks against the pinned Zig exports.
- Add same-thread callbacks, timers, promise jobs, and a POSIX terminal loop with signal wakeups.
- Test rendered state changes and terminal restoration, including JavaScript failure cleanup.

## 0.1.0 - 09/05/2026

- Set up a standard Zig 0.16.0 project with build, run, test, and bundle steps.
- Vendor QuickJS, OpenTUI, its native dependencies, and pinned JavaScript packages.
- Link QuickJS and the OpenTUI ABI statically into an executable with an embedded React smoke bundle.
- Add tests for JavaScript errors and jobs, native buffer lifetime, and Yoga layout.
- Verify macOS arm64 execution and Linux x86-64 musl cross-compilation.
