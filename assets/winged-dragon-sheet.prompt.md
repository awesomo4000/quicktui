# Winged dragon sprite sheet

Generated using the built-in imagegen tool, with `dragon.jpg` as a visual reference.
The output is an RGB draft with a baked checkerboard, not transparent alpha.
Eight poses are arranged in four columns and two rows. Alignment and background
cleanup are still needed before treating this as an animation-ready atlas.

## Generation prompt

Use case: stylized-concept. Create a production sprite sheet for a cute small flying dragon in a terminal game. The supplied dragon photo is a visual reference only: borrow teal jade scales, warm golden belly, orange-red mane, little gold horns and expressive amber eyes, but make a charming chubby baby dragon with two batlike wings, short legs tucked in flight, and a curled tail. Clean hand-painted game sprite illustration, bold readable silhouette, consistent character design. EXACT layout: square 1024x1024 canvas divided invisibly into 4 columns and 2 rows, eight equal 256x512 cells. One whole dragon per cell, always facing right in side profile. Eight successive frames of ONE smooth looping wing-flap cycle ordered left to right, top row then bottom row: wings high, descending halfway, horizontal, low, lowest, lifting halfway, horizontal rising, nearly high. Fixed body center at the exact same relative position (128,256) within every cell, same body scale and orientation, only wings and a small tail flex change. Every sprite wholly contained inside its cell with generous transparent padding. Actual transparent alpha background, no ground, no shadows outside the sprite, no scenery, no grid lines, no labels or text, no checkerboard painted into image. Make wings distinct and anatomically attached, do not duplicate characters within a cell.

## Background correction prompt

Edit this sprite sheet for game production. Preserve all eight dragon poses and their grid locations and illustration style. Remove the entire painted white/light gray checkerboard background and replace it with TRUE transparent alpha pixels. The output must be an RGBA PNG with alpha=0 outside dragons, not an RGB image showing a checkerboard. Do not draw a checkerboard. Do not add anything. Ensure the eight sprites occupy equal regular cells in a 4 column by 2 row grid on a 1024 by 1024 canvas with padding so no tail, wing, or horn touches or crosses its cell boundary. This is a background extraction edit; preserve the dragon characters.
