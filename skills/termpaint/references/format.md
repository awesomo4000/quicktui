# Termpaint file and runtime contract

Current authoritative implementation: `js/paint-model.ts`, `js/paint-cycle.ts`, `js/paint-canvas.ts`, and `src/examples/paint_gif.zig` in the QuickTUI checkout.

## Version 3 JSON

```json
{
  "format": "termpaint",
  "version": 3,
  "width": 256,
  "height": 192,
  "palette": ["32 colors, each formatted as #RRGGBB"],
  "cycle": {"start": 24, "end": 31, "stepMs": 150, "direction": 1, "blend": true},
  "pixels": "one encoded character per pixel, in row-major order"
}
```

The schematic above is not itself a valid picture. Write 32 actual palette colors and exactly `width * height` encoded pixels.

- Width: integer 16–256; height: integer 16–192. They need not match the UI's resize presets.
- Index alphabet: `0123456789abcdefghijklmnopqrstuv.`. Characters `0` through `v` map to opaque indices 0–31; `.` maps to transparent index 32. Never encode a checkerboard into transparent source pixels.
- Pixel `(x,y)` is `pixels[y*width+x]`.
- Palette: exactly 32 `#RRGGBB` strings. Duplicate RGB values in different slots are allowed and useful: their indices can have different animation roles.
- Cycle: one inclusive, contiguous range only, `0 <= start < end < 32`. `stepMs` is an integer 40–2000; `direction` is 1 or −1; `blend` is optional boolean. There are no independently timed multiple ranges yet.
- Whole-loop duration: `(end-start+1) * stepMs`. Smooth mode interpolates between adjacent palette positions, including the wrap; stepped mode shifts whole entries.
- Image data and base palette remain fixed during playback. Hover highlighting, playback phase, selected tools/FG/BG, and renderer selection are not saved.
- Files must fit the native worker's 64 KiB UTF-8 limit. A compact 256×192 version 3 file normally fits. Avoid adding large metadata blobs; keep prompts and provenance in sidecars.
- Version 1 used numeric pixel arrays; version 2 used encoded opaque indices; the loader accepts them. New assets should use version 3 with explicit palette/cycle. Legacy missing palettes default to the original app palette.

GIF export supports 480/960/1440 widths, preserves aspect ratio with rounded height, and rejects heights over 4096. It encodes a full looping cycle; smooth mode targets 25 FPS, capped at 256 frames, so very slow loops use lower FPS. Compressed frame data is limited to 64 MiB. GIF transparency is binary, as is termpaint transparency.

## Practical verification

Parse JSON, check all bounds and alphabet characters, and check the serialized byte size. Render indices through the palette to a PNG for inspection. When validating an animated export, inspect more than its first frame: verify unchanged scenery and movement in intended regions, forward/reverse behavior, and the loop seam. An independent GIF decoder can check frame count, timing, dimensions, transparency, and nearest-neighbor pixel fidelity.
