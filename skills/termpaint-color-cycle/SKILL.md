---
name: termpaint-color-cycle
description: Create imagegen-assisted indexed artwork with intentional palette cycling for termpaint, including waterfalls, neon scenes, fire, and reflections. Use for generation prompts and AI-led asset preparation rather than building human-facing import tools.
---

# Create palette-cycle artwork

Make attractive, editable `.tpaint` scenes whose motion is encoded in the placement of palette indices. Image generation supplies composition and texture; conversion supplies the indexed palette, region selection, and motion phases. Do not claim an ordinary generated RGB image already contains cycle-ready indices.

Read the sibling `termpaint/references/format.md` before writing a painting. Use `termpaint/SKILL.md` when operating the app or exporting GIFs. These files are shipped with the QuickTUI project; locate the checkout rather than assuming an absolute path.

## Generate artwork that can be prepared for cycling

Use the image-generation capability available to the user's assistant, following its own image-generation instructions. If unavailable, explain that limitation and use an existing user-approved source when appropriate; do not silently substitute a different generation service.

Preserve the user's subject and style. Add practical guidance that separates animated materials from static scenery, and ask for readable pixel clusters at the final resolution. A useful starting prompt:

> Create an original 4:3 pixel-art [scene] that remains readable at 256×192. Use a restrained palette and crisp, thoughtfully composed pixel clusters. Keep [static scenery] in [contrasting color family]. Give [moving material] a distinct [color family] with [directional bands/ripples/light ribbons] suggesting its flow. No UI, labels, watermark, blur, or simulated scanlines.

Examples of material separation:

- Waterfall: cyan/blue/white water, warm moss greens and brown/purple rocks; falling ribbons and pool ripples.
- Rainy neon city: saturated cyan/magenta signs and puddles, muted plum architecture; broken horizontal reflection ribbons.
- Waterfront: coral sky and dark skyline stay still; isolate the water below the shoreline before assigning animated neon highlights.
- Fire: reserve amber/orange highlights for flame regions; prevent warm windows, skin, or scenery from joining that range accidentally.

These are suggestions, not required palettes. Color alone does not identify materials reliably. Inspect the generated result and combine color tests with spatial regions or explicit masks. Preserve the generated original and exact prompt in the project before conversion.

## Prepare the indexed painting

1. Resize to the intended canvas, usually 256×192. Inspect at native scale: generated artwork may be much larger and contain misleadingly fine detail. Preserve alpha if the subject needs it.
2. Allocate the 32 palette entries intentionally. Useful starting budgets are 24 static + 8 animated, or 16 scenery + 8 static material colors + 8 animated highlights. Quantize static regions separately from animated highlights. Do not squeeze everything through one generic quantizer and then cycle arbitrary shared colors.
3. Build a cycle ramp whose wrap is intentional. A dark-to-light-to-dark ramp gives a traveling pulse. A hue loop gives neon shifts. Repeated colors can soften the return. Use smooth interpolation when helpful; inspect the wrap instead of assuming it is seamless.
4. Assign a **spatial phase field** to animated pixels. For falling water, phase can grow with y, with small x-dependent offsets for ribbons. Pool ripples can use an elliptical distance from the impact point. Reflections can use horizontal bands with gentle offsets; signs can pulse together or have an authored progression.
5. Map phase modulo the cycle length into the reserved indices. Positive phase along the flow direction and forward palette shifting move the pattern in that direction. Keep much of the source shading static; animating a selected fraction of highlights often preserves depth better than replacing every water pixel.
6. Save the custom palette, indexed pixels, and cycle configuration as version 3 JSON. Keep a PNG preview, source image, prompt, and reproducible preparation script alongside it.

The current runtime has **one contiguous cycle range**, not a multi-layer animation engine. Several regions may share its clock with different spatial phases; they cannot yet have independent speeds. Transparency is a separate non-cycling index. Do not flatten it into the editor's checkerboard.

## Reuse actual examples, adapting their assumptions

In the QuickTUI checkout:

- `examples/paint/waterfall/prepare.py`: static scenery/water palettes plus eight cycling highlight colors; falling ribbons and outward pool ripples.
- `examples/paint/neon-rain/prepare.py`: saturated neon masks, pulsing signs and wet-road reflections.
- `examples/paint/sunset-harbor/prepare.py`: water-region restriction keeps the sunset and skyline static.
- Each directory has `PROMPT.md`, `source.png`, a static PNG, and the resulting `.tpaint`.

Read a relevant script before adapting it. The example scripts use Python's standard library plus macOS `sips` for decoding/resizing; they are not cross-platform importers. On another OS, use an available decoder or adapt that stage. The masks contain scene-specific coordinates, thresholds, and phase fields: never reuse those blindly on a differently composed image. Write a new sibling asset directory so experimenting does not overwrite the examples.

## Judge the motion, not only the still

Load the painting in termpaint, play the cycle, and inspect a complete loop. Check that scenery remains stable, intended regions animate, highlights have a coherent direction, and the wrap does not flash. Hover individual palette entries to inspect affected pixels. Adjust masks, ramps, phase fields, and step duration based on the result. Reduce animation coverage if the effect becomes noisy or obscures the original lighting.

Blocks is the default; Kitty displays all stored pixels but may smooth their enlargement. The stored resolution does not change when switching output. Do not mistake the more detailed Kitty view for a higher-resolution source file.

When requested, export through termpaint's GIF dialog. The native exporter enlarges the indexed canvas with nearest-neighbor scaling and uses the saved palette cycle. Report which stages were generation, conversion, and direct export. Deliver editable paintings as well as requested previews/GIFs so the user can remix the work.
