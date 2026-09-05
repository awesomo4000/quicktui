# Changelog

## Unreleased - 09/05/2026

- Increase the message demo command queue from 8 to 256 entries so repeated bursts can wait behind active work.

- Add C to clear completed requests and their replies while preserving active work.

- Keep complete request and reply histories in independently scrollable message panels, following new entries when at the bottom.

- Add random message batches with mixed concurrent waits and serial pairs, varied durations, and completion timing checks.

- Add V to cycle solid, segmented, and thin progress bars in the messages demo.

- Expand message progress bars to fill each row and right-align their percentages.

- Add a ten-request concurrent spread to the messages demo and label heartbeat pause explicitly.

- Add a native messages demo with a Zig worker thread, bounded queues, streamed progress, and a responsive React counter.
- Add an optional application-owned message endpoint to the host poll loop, with copied strings and UI-thread delivery.

- Share one embedded JavaScript dependency graph across the dragon, mouse, gallery, and smoke examples instead of shipping duplicate framework bundles.
- Initialize only the selected example and verify shared library modules occur once during bundling.

- Tighten gallery sidebar spacing, pad labels on the left, add subtle hover shading, and show muted overflow arrows instead of a visible scrollbar track.

- Add an eight-page widget gallery covering the remaining React widgets plus sliders and tables.
- Support focus traversal, paste, text editing, selection, cursor display, framebuffer widgets, and scrolling.
- Keep code rendering plain; use bundled Marked tokens for Markdown style/conceal captures and preserve native diff colors without a worker runtime.
- Add gallery interaction and terminal cleanup tests; keep the original dragon and mouse examples available.

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
