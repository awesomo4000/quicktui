# Demo assets

`dragon.jpg` is the dragon picture used by QuickTUI. It is embedded in the executable
by `scripts/counter-bundle.ts`, so running the demo needs no external image files.

Copied unchanged from `vendor/opentui/packages/examples/src/assets/dragon.jpg`
at OpenTUI commit `7581976f4d2c917fd5ae5266c8bc61f0e44fc933`.
See the upstream license in `vendor/opentui/LICENSE`.

`dragon-frames/` contains eight alpha frames extracted from the generated sheet
for the in-place animation preview. `frames.json` records their source rectangles
and playback order. Each is padded to a common canvas, reduced to 176 × 208 pixels,
and decoded once at startup. All eight poses are included at 8 FPS.

The `.rgba` siblings are 176 × 208, 8-bit RGBA in row order. The bundle embeds
these raw pixels to avoid the PNG sprite transport failure observed in Herdr.
Regenerate each with `magick FRAME.png -depth 8 rgba:FRAME.rgba`.
