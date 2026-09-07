# neon-rain

Generated with the built-in image_gen tool. Original retained as source.png.

## Prompt

Create an original landscape 4:3 pixel-art vaporwave city scene for a 256x192 indexed-color animation. Rainy nighttime street canyon, distant geometric skyscrapers, small shops, luminous magenta and cyan neon light panels with abstract geometric markings rather than legible lettering, puddles reflecting their colors, a quiet atmospheric retro game background. Excellent readable pixel clusters, limited-palette 1990s adventure-game art, deep plum/navy architecture, peach horizon, electric cyan/magenta accents. Wet street fills lower third with horizontal broken reflection ribbons designed for palette cycling. Static buildings must be mostly muted warm purple; animated luminous reflections and signage strongly saturated cyan and magenta. No people, no text, no UI, no watermark, no blur, no scanline overlay. Rich composition at the same low-resolution scale as a 256x192 painting.

## Preparation

Run `python3 examples/paint/neon-rain/prepare.py` on macOS. The converter creates a 256×192 painting with 24 static palette colors and eight cycling neon colors. A color/region mask selects highlights; spatial phase bands supply motion. These motion fields are authored during conversion, not extracted animation from the generated still. The PNG is a static preview; the .tpaint file includes palette cycling settings.
