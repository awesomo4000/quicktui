# Dither3D source for the QuickTUI graphics lab

Author: Rune Skovbo Johansen.
Source: https://github.com/runevision/Dither3D
Pinned commit: 34fa85832268dc0649aad24b1b4fe07420782724
License: MPL-2.0, included in LICENSE.md.

The original shader, texture generator, 4x4 R8 volume, and brightness ramp
are preserved here. scripts/extract-dither3d.py extracts the volume and ramp
into src/examples/dither3d without requiring Unity or image packages.

src/examples/dither3d.zig is a CPU adaptation of the grayscale shader,
also under MPL-2.0. It uses perspective-correct UVs and their screen
derivatives, singular-value frequency estimation, trilinear sampling of
the original fractal pattern, and the original brightness ramp.

This demo exposes a hard 1-bit threshold. It omits radial compensation,
RGB/CMYK modes, and alternative seam UVs. Extreme grazing angles and
low output resolution can still alias. It is not a complete Unity port.
