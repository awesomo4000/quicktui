# Waterfall source

Generated with the built-in image_gen tool. The original is preserved as source.png.

## Prompt

Use case: stylized-concept. Asset: original pixel-art waterfall background for an indexed-color terminal paint program and palette cycling. Create a beautiful serene forest grotto with a broad waterfall pouring over a mossy rocky ledge into a turquoise pool, layered warm moss green foliage and brown violet rocks, soft golden light from above. Composition landscape 4:3, waterfall clearly separated from rocks, central vertical falls with visible narrow horizontal broken ribbons of cyan, blue and pale white foam; pool spreading across lower third with curved ripple bands. Authentic meticulously composed early-1990s adventure-game pixel art, crisp pixel clusters, restrained 32-color appearance, readable at 256x192, rich scenery without tiny visual clutter. Water exclusively cool blue/cyan/white, vegetation warm green and golden, rocks warm brown/purple so we can isolate water for animation. No text, no UI, no border, no characters, no blur or simulated scanlines. Water motion should be suggested by directional bands, not smooth photographic gradients.

## Preparation

Run `python3 examples/paint/waterfall/prepare.py` on macOS to resize and quantize the image into 32 palette entries. Entries 0–15 hold scenery, 16–23 hold static water, and 24–31 animate highlights. The converter assigns downward flow phases on the waterfall and expanding ripple phases in the pool. This is an authored animation field, not motion recovered from the generated still image. The native-sized PNG is a static preview; waterfall.tpaint stores the palette and cycle settings.
