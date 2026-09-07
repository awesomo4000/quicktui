---
name: termpaint
description: Create, edit, preview, and export indexed pixel artwork with termpaint. Use when a user wants an AI to operate termpaint, prepare .tpaint assets or sprite sheets, or export its palette animations as GIFs.
---

# Work with termpaint

Termpaint is a standalone terminal paint app in the QuickTUI repository. It has no built-in AI service. Use the user's available image tools, filesystem, and authorized terminal controls; do not assume a particular assistant, terminal emulator, or pane ID.

## Choose the workflow

- **Operate the paint app:** use mouse events for drawing and palette selection, with the shortcuts below. Inspect the actual target pane before sending input.
- **Create precise sprites or import artwork:** generate a `.tpaint` file outside the app and open it by filename. Read [the format reference](references/format.md) before writing one. The app currently does not import arbitrary PNG/JPEG files directly.
- **Create animated scenery:** read the sibling `termpaint-color-cycle/SKILL.md` for generation prompts, palette partitioning, and motion preparation.

Find the QuickTUI checkout containing `build.zig`, `js/termpaint.tsx`, and `examples/paint/`. From that directory:

```sh
zig build -Doptimize=ReleaseSmall
zig-out/bin/termpaint path/to/picture.tpaint
```

Zig 0.16.0 is required by this project. Normal builds consume the checked-in JS bundle. Only after editing JS, regenerate it with `zig build bundle-termpaint` using Bun. Do not change app code just to produce new artwork.

## Preserve the user's work

Check the title's `*` dirty marker before switching files. Save pending edits and verify success. The app asks before replacing existing files; treat confirmation as a real overwrite decision. Use a new filename for a new picture and keep originals for generated/converted assets. Do not touch unrelated panes, user presets, or another drawing merely to demonstrate the app.

Use Open / Ctrl+O to enter or paste a .tpaint path. Opening prompts before discarding unsaved changes; invalid files leave the existing painting intact. When using the CLI instead, do not type a shell command until the pane has returned to a shell. Never assume a pane ID from an earlier task still identifies this app.

## Controls

| Action | Input |
|---|---|
| Pencil / brush / spray / flood fill | 1 / 2 / 3 / 4, or tool buttons |
| Foreground color | Click palette swatch |
| Background color | Ctrl-click or right-click swatch |
| Paint foreground | Left-click/drag canvas |
| Paint background | Ctrl-click/drag or right-click/drag canvas |
| Transparent paint | E or Transparent; Ctrl-click Transparent selects transparent background |
| Swap FG/BG | X |
| Brush radius | [ / ], or − / + buttons |
| Undo / redo | Z / Y |
| Open / save | Ctrl+O / Ctrl+S (also S), or Open / Save buttons |
| New / resize | N / R |
| Blocks / Kitty | M; Kitty requires terminal confirmation |
| Play/pause palette cycle | C |
| Reverse / slower / faster | V / − / = |
| Cycle range | Select two opaque FG/BG colors; click Range = FG/BG |
| Inspect color usage | Hover palette swatch; its pixels temporarily turn white |
| GIF export | G or GIF; Left/Right selects 480/960/1440 width, Enter exports, Esc cancels |
| AI Help | H or AI Help |
| Quit | Q; unsaved changes trigger confirmation |

Cycle Reset restores the original palette phase and stops playback. Smooth blend/Stepped changes interpolation. Transparent pixels never participate in a cycle.

Terminal mouse positions are **cells**, not source pixels. Read `PaintCanvas.geometry()` and `point()` in `js/paint-canvas.ts` if implementing mouse automation: the canvas is centered and letterboxed, and terminal resize changes its bounds. Do not use coordinates guessed from a different pane size. For raw SGR events, Ctrl adds 16 to the button code; left drag adds 32. Press, drag, release must remain a coherent stroke. Send modal-opening keys and their confirmations as separate events after the UI updates.

Blocks is the default and samples two vertical colors per terminal cell. Kitty displays the full pixel image stretched over that area and may look smoothed. The title reports **stored canvas dimensions**, not physical screen pixels. Increasing terminal size does not increase stored image resolution.

## Validate and deliver

Inspect the converted image at native size and enlarged with nearest-neighbor scaling. Verify dimensions, palette length, transparency, and pixel count before opening it. In the app, verify the loaded filename/status and exercise the relevant animation or drawing interaction.

GIFs are exported directly by the native Zig worker, without an external converter. They capture the full source canvas, not a screenshot of its terminal-cell sampling, UI, cursor, hover highlight, or checkerboard. Size is proportional, scaling is nearest-neighbor, and transparent pixels remain transparent. The loop uses the saved cycle range, direction, speed, and blending; playback phase is not saved. Output is `<painting-name>-<width>.gif` beside the painting.

Report the editable file and any requested exports. Distinguish image generation, conversion, and export; do not imply that the generator authored indexed animation or that a GIF was post-processed when it came directly from termpaint.
