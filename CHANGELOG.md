# Changelog

## Unreleased - 09/09/2026

- Extract shared terminal application lifecycle from React; add `quicktui/core`,
  the `quicktui/react` alias, and an independent vanilla JS consumer with a
  React-free bundle check. Existing React APIs use the shared runtime.

- Add public `useKeyboardEvents` with runtime component enable/release filtering, reset notifications, automatic unsubscription, and explicit event consumption. The game uses the hook.

- Add opt-in keyboard enhancement flags, normalized key metadata, release routing, held-key/reset helpers, and game/keyboard diagnostics with deterministic and injected PTY tests. Direct Ghostty letter events were verified; the tested Herdr 0.8.2 path still drops printable releases.

## Unreleased - 09/08/2026

- Defer reload until queued input and partial paste/key sequences finish; extend 06b with retained draft, caret, selection, and scroll, plus fragmented-paste and input-readiness regression tests.

- Expose opt-in reload through `runApp`, public JS snapshot/reload helpers, and an independently built textarea consumer with draft-restoration tests.

- Label live component loading 06a and add experimental 06b whole-runtime replacement, with saved/unsaved counters, retained presentation, bounded preparation, broken-bundle recovery, and headless/PTY regression tests.

- Move the demo renderer into native host ownership so React and QuickJS can retire while the last frame remains alive. Final host shutdown still destroys the renderer and restores the terminal; headless demos verify text-frame retention across runtime teardown.

- Begin persistent UI reload groundwork by separating terminal-session cleanup and stopping event dispatch and endpoint sends after a UI exit or failure. Add repeated callback-boundary regression tests.

## Unreleased - 09/07/2026

- Add explicit endpoint closure and send outcomes, bounded paste delivery, public application startup and consumer bundling, and disposable stress/consumer tests.

- Add a project introduction, dragon logo, and cycling-art preview; keep the detailed demo documentation in GUIDE.md.

- Put Open and Save first in the termpaint toolbar, add a Ctrl+O path dialog with paste and unsaved-change protection, and move the filename to its own line.

- Add bundled termpaint operating and color-cycle creation skills, with an AI Help dialog that copies complete guidance to the terminal clipboard.

- Add imagegen Neon Rain and Sunset Harbor scenes with 256×192 indexed artwork and cycling neon reflections.

- Add native animated GIF export at 480/960/1440 pixels wide with proportional nearest-neighbor scaling, transparency, full palette loops, and atomic file replacement confirmation.

- Save per-painting palettes, add smooth color-cycle interpolation, and include an imagegen waterfall with directional water animation.

- Default termpaint to Blocks and add non-destructive palette cycling with saved range/speed/direction, play/pause/reset controls, and palette-hover pixel highlighting.

- Support Ctrl-click and Ctrl-drag as background-color actions in termpaint, including palette and transparency selection.

- Add transparent painting and checkerboard previews, version 3 alpha-capable files, and an original twenty-tile player/monster sprite sheet with an alpha PNG.

- Add automatic Kitty graphics and a block fallback to termpaint, undoable canvas resizing up to 256×192, and compact painting files with legacy loading.

- Add standalone termpaint with a separate JS bundle, retro palette and tool panels, pencil/brush/spray/fill, undo/redo, and native .tpaint load/save.

- Make Down at the bottom of the editor move to the end of the final line.

- Replace the editor filename bar and function-key shortcuts with an Alt+F File menu, Ctrl+O/Ctrl+S dialogs, and an arrow-navigable Recent Files submenu.

- Add an editor demo with UTF-8 load/save through a native worker, shared widget input, unsaved-change prompts, and confirmed atomic file replacement.

## Unreleased - 09/06/2026

- Expose OSC 52 clipboard writes in the demo bridge and exercise the copy button through mouse input; report copy failures without exiting the lab.

- Add a live graphics settings-code box with a border copy button and a reversible, append-only QT1 codec with permanent defaults.

- Expand lab presets to 128 scrollable slots with paginated worker replies and compact automatic names carrying a settings fingerprint.

- Generate preset names from current lab settings, preview automatic names, and distinguish automatic from custom names when overwriting slots.

- Add surface two-shade mode with H/L dark-ink controls, colored gaps inside projected faces, and dim braille/glyph backgrounds.

- Add a surface-fractal color wash that blends projected face hues while preserving the monochrome dot mask, with Y/U strength controls.

- Add surface-fractal color dithering with face-colored ink in pixel, half-block, braille, and glyph output.

- Raise shape zoom from 1.4× to 8× for close inspection of surface dithering.

- Add independent graphics-lab rotation speed controls, including zero, reverse rotation, and fine steps down to 1/65,536× with double-precision angle accumulation, with preset persistence.

- Vendor Poolside 0.2.0 and replace four terminal-buffer plane pointer results with opaque, generational read views; validate byte bounds and revoke views on buffer resize/destruction.

## Unreleased - 09/05/2026

- Add a separate live-JavaScript demo that loads external scripts into the running React page, supports additive components and file watching, and recovers from load/render errors.

- Add nine persistent graphics presets with descriptions, a keyboard/mouse save-load panel, and atomic native-worker file writes. Restore the saved pose and display settings while retaining the current viewport.

- Add a pure braille charset to native glyph selection, without ASCII or punctuation.

- Preserve source colors in braille and native glyph modes; fit foreground/background colors for quadrant and block sets while keeping dithering monochrome.

- Add seven Phosphor glyph sets with six-region shape matching on the native worker and G selection in the graphics lab.

- Add 1–120 FPS controls and delivered-frame statistics; rate-limit native rendering under key repeat and advance animation by elapsed time.

- Extend the graphics lab with a 4D hypercube, Mandelbrot explorer, half-block and braille output, brightness/contrast controls, and Bayer comparison.
- Vendor Dither3D at a pinned revision and adapt its grayscale surface fractal dithering to the Zig CPU renderer, with the original lookup textures and MPL-2.0 attribution.

- Prevent pending graphics frames from being disposed during zoom, and avoid deleting Kitty images before uploading replacement frames.

- Add a separate graphics lab with software-rendered 3D surfaces, shaded and wireframe modes, palettes, mouse rotation, and zoom.
- Render on a Zig CPU worker and deliver frame-ready messages with binary buffer lookup, dropping stale frames.
- Display animated RGBA frames through native Kitty graphics with a terminal-block fallback.

- Send unsolicited blink events from the native worker every random 1–5 seconds, including while idle.
- Report grid dimensions to the native worker, which chooses 1–10 unique squares to flash twice together on each event.

- Overlay a subtle draggable scroll thumb on each history pane border without reserving a content column.

- Prevent segmented and thin progress bars from retaining their previous width and clipping percentages when panes narrow.

- Add a pulsing multicolor activity grid beneath native replies, with fading verbs and oscillating values.
- Use one-cell vertical and horizontal draggable dividers for the three-pane messages layout.

- Replace the divider arrow with a subtle vertical hover and drag cue.

- Preserve the divider grab offset, apply explicit column widths, and flush input updates synchronously to avoid drag jumps and lag.

- Widen the requests pane by default and add a mouse-draggable divider to the messages demo.

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
