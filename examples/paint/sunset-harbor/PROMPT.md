# sunset-harbor

Generated with the built-in image_gen tool. Original retained as source.png.

## Prompt

Create an original landscape 4:3 pixel-art vaporwave waterfront city background, designed to remain beautiful at 256x192 pixels with an indexed palette. Broad tranquil bay in the foreground and a futuristic skyline of art-deco towers across the water, huge soft coral setting sun behind towers, a couple of dark palm silhouettes framing edges, electric pink and cyan architectural lights reflected in the dark violet water. An elegant dreamy retro-futurist twilight scene, different from a street canyon. Skyline in middle third, calm water fills bottom half with clearly designed horizontal broken reflected light bands. Crisp pixel clusters, subtle ordered dithering in sunset sky, 1990s adventure-game pixel art, restrained palette, static architecture deep plum, sky coral and peach, animated highlights saturated cyan and pink. No people, no readable text, no UI, no border, no watermark, no blur, no scanlines.

## Preparation

Run `python3 examples/paint/sunset-harbor/prepare.py` on macOS. The converter creates a 256×192 painting with 24 static palette colors and eight cycling neon colors. A color/region mask selects highlights; spatial phase bands supply motion. These motion fields are authored during conversion, not extracted animation from the generated still. The PNG is a static preview; the .tpaint file includes palette cycling settings.
