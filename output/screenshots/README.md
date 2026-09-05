# Herdr pane capture

Use `herdr pane layout --pane wP:p3` to obtain the pane rectangle in terminal cells.
Locate Ghostty's window ID and bounds with CoreGraphics `CGWindowListCopyWindowInfo`.
Capture the visible window with `screencapture -x -o -l WINDOW_ID WINDOW.png`.
Account for the window title bar, terminal padding, font cell size, and Retina scale
when converting the pane rectangle to image pixels. Verify the crop visually.

For the first capture here, Ghostty window 275 was 5338 × 3066 pixels and the
verified pane crop was `2528x2036+2796+152`. These values are a calibration for
that window configuration, not constants: remeasure after resizing or font changes.
Focus the workspace immediately before capture; API text snapshots cannot prove
that pixel graphics are visible. Keep other panes out of the saved crop.

`herdr-wP-p3.png` shows the blank PNG sprite. `herdr-wP-p3-rgba.png` shows
frame 1 using raw RGBA, and `herdr-wP-p3-animation.png` shows frame 3 during playback.

## Widget gallery

- `herdr-gallery.png`: live Text & layout page.
- `herdr-gallery-markdown.png`: live Markdown emphasis, heading, quote, and table after the Marked adapter fix.

The pane split changed during gallery testing: `wP:p3` moved to cell x=101 with
width=104, y=1, height=36. The updated Retina crop was
`2684x2036+2640+152`. Re-query the layout before reusing it.
