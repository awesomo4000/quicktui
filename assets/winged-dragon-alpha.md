# Alpha sprite sheet

`winged-dragon-sheet-alpha.png` is the transparent RGBA version. Verified alpha
ranges from fully transparent to fully opaque and visually checked against the
demo's dark background. The original RGB drafts are retained separately.

The built-in imagegen tool made `winged-dragon-sheet-chroma.png` using this prompt:

Prepare this existing eight-frame dragon sprite sheet for chroma-key extraction. Preserve the exact eight dragons, poses, scale, style and positions. Replace ALL checkerboard background with one perfectly flat solid vivid MAGENTA RGB(255,0,255), hex #FF00FF. Include magenta in every gap between wings, legs, body and tail. Clean hard silhouette edges with minimal antialiasing. No magenta anywhere inside the dragons. No shadows, no glow, no gradients in background, no checkerboard, no transparency simulation. Keep all eight sprites whole and separate in the same four-column two-row arrangement. This is a background-only edit, not a new character design.

ImageMagick extracted alpha with this reproducible chroma-key operation:

```sh
magick assets/winged-dragon-sheet-chroma.png -alpha on -channel A -fx 'max(0,min(1,1-(min(r,b)-g-0.05)/0.25))' +channel assets/winged-dragon-sheet-alpha.png
```

The sheet is 1254 × 1254 with eight poses. Frame alignment remains a separate
step before animation; it is not an exact equal-cell atlas yet.
