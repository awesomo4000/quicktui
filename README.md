# QuickTUI

A standalone React/OpenTUI terminal counter and graphics demo built with Zig 0.16.0 and embedded
QuickJS. React state updates drive OpenTUI's existing host configuration,
box/text components, native text rendering, and Yoga layout.

## Build and run

Install **Zig 0.16.0**. macOS also requires the Xcode command-line tools and SDK.
All project dependencies and generated JavaScript are vendored. Normal builds
need no network access, Node, npm, Bun, or separate QuickJS installation.

```sh
zig build
zig build run
```

The executable is `zig-out/bin/quicktui`. Its controls are:

- Space, Up, or `+`: increment.
- Down or `-`: decrement.
- `R`: reset.
- `Q` or Ctrl+C: exit and restore the terminal.

The counter redraws after state changes and terminal resizing. OpenTUI's input
parser handles coalesced keys, split escape sequences, and terminal replies.

The demo includes an embedded dragon picture. It starts with colored terminal blocks
and switches to Kitty pixel graphics only after the matching capability probe
returns `OK`. Rejection or a two-second timeout keeps the block fallback.

Inside tmux, enable passthrough for the demo window:

```sh
tmux set-option -w -t quicktui allow-passthrough on
```

QuickTUI forwards `TMUX` and terminal identity before native setup. OpenTUI then
wraps the probe and image commands in tmux DCS passthrough, doubling their embedded
escape bytes. This prevents tmux from interpreting the graphics probe as a pane
title. No unwrapped retry is sent on timeout. Any intervening terminal layer must
also pass graphics commands and replies through. Pixel images use Unicode
placeholder cells under tmux, so pane redraws preserve their location. This
requires an outer terminal with Kitty Unicode placeholder support.

```sh
zig build -Doptimize=ReleaseSmall
zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSmall --prefix zig-out/linux-x86_64
```

macOS arm64 has been built and run, including inside tmux. Linux x86-64 musl
cross-compiles to a static ELF executable but has not been run on Linux here.
Only aarch64 and x86-64 on macOS/Linux are enabled. macOS executables use normal
system libraries and frameworks, with no adjacent OpenTUI dynamic library.

In a restricted environment, add `--global-cache-dir .zig-cache/global` to keep
Zig's cache writes inside the project.

## Tests

```sh
zig build test
zig build test-terminal
zig build test-tmux
```

`test` runs Zig unit tests and the counter's headless integration test. It checks
rendered count changes, split arrow-key input, reset, resizing, Unicode output,
and React effect cleanup. The headless test uses real OpenTUI native buffers.

`test-terminal` additionally requires Python 3. It uses disposable PTYs to check
resizing and restoration after Q, Ctrl+C, SIGINT, SIGTERM, SIGHUP, and an injected
JavaScript exception. Fault injection uses a separate test executable.
It also tests direct and tmux-wrapped graphics output, fragmented confirmation,
unrelated replies, rejection, and timeout. `test-tmux` requires tmux and checks
pane-title preservation in a private disposable server, with passthrough on/off.

The original dependency smoke test remains available:

```sh
./zig-out/bin/quicktui --smoke
./zig-out/bin/quicktui --self-test
```

## Mouse example

The original dragon demo remains the default. Run example 02 separately:

```sh
zig build run -- --mouse
```

Hover over the click pad, try left/middle/right buttons, drag from the orange pad
and release outside it, and scroll over the purple wheel control. The last event
shows pane-relative cell coordinates and modifiers. Press Q to exit.

Mouse input uses OpenTUI's parser and native hit grid, with React `onMouseDown`,
`onMouseUp`, `onMouseOver`, `onMouseOut`, `onMouseDrag`, and `onMouseScroll`
handlers. Events bubble through the renderable tree. Drag and release remain
routed to the pressed target while the pointer leaves its bounds. This example
does not yet provide text selection, focus navigation, or drag-and-drop widgets.
Multiplexers must forward mouse events to the application. Terminal or multiplexer
shortcuts can intercept modified clicks.

`zig build test` includes the mouse example's real parser/rendering test.
`zig build test-mouse` checks mouse mode setup and restoration in disposable PTYs.

## Widget gallery

```sh
zig build run -- --gallery
```

Click a page in the sidebar or press F1/F2 to move between pages. Click an input
or press Tab/Shift+Tab to move focus. Escape or Ctrl+C exits; ordinary letters,
including Q, can be typed in fields.

| Page | Widgets and interactions |
| --- | --- |
| Text & layout | Inline styles, links, Unicode, borders, flex layout |
| Input & textarea | Typing, paste, submit, multiline editing, keyboard selection |
| Select & tabs | Focus with Tab or a click, arrows to move, Enter to choose |
| Scroll & sliders | Trackpad/wheel scrolling, scrollbar dragging, altitude slider |
| ASCII fonts | Tiny, block, and shade fonts using framebuffers |
| Code & lines | Code text with a line-number gutter |
| Diff | Click to switch between unified and split views |
| Markdown & tables | Headings, emphasis, lists, quotes, and a bordered table |

Each page scrolls when its contents exceed the available terminal height.
The dragon and mouse examples remain available without flags and with `--mouse`.

`zig build test` visits every gallery page and checks editing, paste, selection,
list/tab navigation, scrolling, sliders, diff switching, Markdown, and resizing.
`zig build test-gallery` checks terminal setup and cleanup in disposable PTYs.

## Editing the example

Edit `js/counter.tsx`, `js/mouse.tsx`, `js/gallery-app.tsx`, or `js/messages.tsx`, then regenerate the checked-in bundles with Bun:

```sh
zig build bundle
zig build test
zig build
```

Bundle regeneration was tested with Bun 1.3.14. It resolves packages from
`vendor/js/node_modules`; no install step is needed. `bundle` also regenerates
the fixed C wrappers and checks their signatures against the pinned native source.


## Native messages example

Run example 04 with `zig build run -- --messages`.
Press **S** or click **Job** to enqueue work. **B** sends a burst of 12,
and the command queue holds 256 waiting commands plus the active work.
Several bursts can wait while a job runs. **Space** increments a local UI counter.
**F** starts a spread of ten concurrent requests with a shared 500 ms wait.
The spread is one atomic queue command containing ten logical requests, so all
ten are admitted or rejected together. The worker models overlapping I/O waits
on one thread; CPU work would require a worker pool for parallel execution.
Ordinary jobs and spread batches are taken from the command queue in order.
**R** runs a random batch of ten jobs, mixing concurrent waits with two or three
serial pairs. Each runs for 1–2.2 seconds; the batch targets completion below
five seconds after it starts. Batches queued behind earlier work wait their turn.
**V** cycles solid, segmented, and thin progress bars. **C** clears completed
requests and their replies, keeping queued and running work.
A decorative Activity pane below Replies pulses a multicolor grid at 20 FPS,
with fading verbs and oscillating values. The Zig worker also sends an unsolicited
`blink` event at random 1–5 second intervals, both idle and while working. That
message contains 1–10 unique square IDs selected by Zig, capped at the grid size.
The grid reports its dimensions through `grid:columns:rows` messages on layout
changes. Native code keeps the latest dimensions independently of the job queue.
All selected squares flash twice together over 800 ms before resuming their
underlying pulses. Events for an old grid size are ignored rather than remapped. The reply log records each native blink. JS animates the visual
response; it does not schedule or synthesize the triggering events.
Drag its horizontal divider to change the right-side height split. Both dividers
are one terminal cell thick.
Requests starts wider than Replies. Drag the divider between them to resize
the panels; the progress bars follow the available width.
Both panels retain the full session history. Scroll each with the trackpad or the single thumb overlaid on its right border.
The thumb brightens on hover; no scrollbar column is reserved. At the bottom, it follows new entries; scroll up to browse older
entries without being pulled back down. Panel titles show the total counts.
**P** pauses the UI heartbeat, and **Q** exits. Native replies still arrive with
the heartbeat paused because their pipe wakes the host poll loop.

The React app is in `js/messages.tsx`; its Zig worker is in
`src/examples/message_worker.zig`. The worker uses `std.Thread.spawn`, two
mutex-protected bounded queues, a condition variable, and a nonblocking wake
pipe. It sends progress every 100 ms, then a completion event. This is simulated
work, with no sockets or nREPL dependencies.

The library hook is `MessageEndpoint` in `src/root.zig`:

```zig
var worker: Worker = .{};
try worker.start();
defer worker.stop();
const endpoint = worker.endpoint();
try quicktui.runWithMessages(bundle, "messages", false, &endpoint);
```

JS calls `__host.postMessage(text)`, which returns false when the command queue
is full. The host delivers replies to `globalThis.__message(text)` on the UI
thread, where the demo updates React state. Strings are copied across the
boundary, limited to 4096 UTF-8 bytes. The demo sends decimal request IDs and
receives JSON progress events; the library treats the payload as opaque text.

The endpoint callbacks must return promptly. `send` copies a command before
returning; `receive` copies one event into the host buffer or returns -1 when
empty. The endpoint owns its wake descriptor and keeps it readable while events
remain queued. The host drains at most 32 messages per turn before servicing
JS timers, promise jobs, and rendering. Native threads never enter QuickJS.

The application owns worker startup and shutdown. On exit, this demo unmounts
React, signals the worker to stop, discards unfinished demo jobs, joins the
thread, and closes its pipe. A production backend can choose different shutdown
and cancellation semantics.

`zig build test` checks queue copying, capacity, FIFO order, streamed completion,
React input, timers, and cleanup. `zig build test-messages` uses disposable PTYs
to check native wakeups with the UI heartbeat paused and terminal restoration
after Q or SIGTERM with work queued.

## Graphics lab

Run example 05 with `zig build run -- --lab`. The messages demo stays available
as `--messages`.

- **1–5** selects torus, orb, sheet, 4D hypercube, or Mandelbrot.
- **Drag** rotates geometry or pans the fractal; **scroll** zooms.
- **M** cycles Kitty/automatic fallback, Unicode half blocks, braille, and native glyphs.
- **G** enters native glyph mode and cycles ASCII, shades, quadrants, braille with punctuation,
  ASCII plus braille, box drawing, blocks, and pure braille.
- **D** cycles color, grayscale, screen-space Bayer, and surface fractal dithering.
- **B / N** raises/lowers brightness; **K / J** raises/lowers contrast.
- **O / I** enlarges/shrinks surface dither dots.
- **W** toggles wireframe; **C** changes palette; **P** pauses animation.
- **- / =** lowers/raises the target frame rate through 1, 5, 10, 15, 20, 30, 45, 60, 90, and 120 FPS.
  The delivered FPS counter measures native frames received by JS in the last second,
  not physical terminal presentation. Rotation follows elapsed time, independently
  of key repeats and the selected frame rate.
- **T** visits a Mandelbrot detail; **R** resets view and tone adjustments.
- Arrow keys rotate or pan; **Q** exits.

**F** opens 128 numbered preset slots in a scrollable picker. Select with
arrows, **Page Up/Down**, **Home/End**, or the mouse; **1–9** jumps to the first
nine slots. The wheel/trackpad scrolls the list. **Tab** edits the description, **S** saves the current settings, and
**Enter** loads. While editing, **Enter** saves the description and settings;
**Escape** leaves editing or closes the panel. Saving to an occupied slot
replaces it.

Presets are versioned JSON files in `.quicktui-presets/1.json` through
`128.json`, relative to the app's working directory. This folder is ignored by
Git. Each stores scene, current rendered angle, camera/fractal position, zoom,
pause state, frame-rate target, palette, tone, brightness, contrast, dot size,
output mode, and selected charset. Loading keeps the current viewport size.
The native worker writes a temporary file, flushes it, and atomically replaces
the selected slot. Invalid presets report an error instead of changing the
scene. Self-tests use disposable directories under `/tmp`, never local slots.

The hypercube rotates in three 4D planes before perspective projection into 3D
and then 2D. Shaded faces, visible edges, and dashed hidden edges expose its
structure. Mandelbrot uses double-precision coordinates, smooth escape coloring,
and a bounded 320-iteration calculation. Its zoom range ends at 10 billion;
the fixed iteration budget limits detail near the set boundary.

The Phosphor hypercube, Mandelbrot, and ASCII cube experiments inspired these
demos. Their terminal loop is not imported.

The surface dither is a partial CPU adaptation of Rune Skovbo Johansen's
[Dither3D](https://github.com/runevision/Dither3D). Its pinned shader, original
lookup textures, generator, and MPL-2.0 license live in `vendor/dither3d`.
The adapted `src/examples/dither3d.zig` retains MPL-2.0 licensing. A standard
Python script extracts the lookup bytes; the normal build needs neither Python
nor Unity. It uses perspective-correct surface UVs and screen derivatives to
choose self-similar texture layers. Grayscale hard 1-bit output is implemented;
radial compensation, alternate seam UVs, and RGB/CMYK output are not. Low
resolution and grazing angles can still alias. Mandelbrot uses complex-plane
coordinates as its surface.

Half blocks and braille use a custom OpenTUI renderable, so they participate in
normal cell diffing and need no graphics protocol. Braille shares one source-derived foreground
color across each cell's eight dots; it is most useful for wireframes. These
modes currently resample the same 240 × 160 native frame.

Native glyph mode adapts Phosphor's six-region shape matching and Fira Code
measurements from `examples/ascii-cube.zig`. Font differences can affect how
well a selected character matches the samples. Matching and area sampling run
on the Zig worker; UTF-8 rows travel after the RGBA pixels in the binary frame.
Each cell also carries foreground/background RGB values. ASCII, braille,
shades, and box glyphs use source-derived foreground colors. Quadrant and
block sets fit two colors to their glyph coverage. Both black-and-white
dither modes use white ink on black. JS batches adjacent cells with equal
colors into runs through OpenTUI without searching the glyph sets. The viewport is
bounded to 240 columns by 80 rows, and size changes reach the worker within
the half-second metrics interval. Existing half-block/braille modes still do
their conversion in JS.

`src/examples/lab_raster.zig` performs CPU projection, triangle rasterization,
depth buffering, and lighting on the worker in `src/examples/lab_worker.zig`.
React sends scene settings through the message endpoint. The worker publishes a
small `frame-ready` message and keeps the latest 240 × 160 RGBA frame in native
memory. `__host.takeBuffer(id)` copies that frame into a JS ArrayBuffer under a
short native lock, then releases it. Pixels never pass through JSON. This first
version uses a binary copy rather than shared JS/native memory.

React imports those pixels into a native image and displays it using Kitty
graphics after a successful probe, or terminal blocks otherwise. The worker
defaults to ten frames per second, enforces its deadline even under input floods, and coalesces both pending frames and scene updates,
so a slow UI does not accumulate work. Superseded frame IDs return null. React
releases replaced or skipped image handles. QuickJS and all OpenTUI image calls
remain on the UI thread; only software rasterization runs on the worker.

The graphics lab is CPU-only. This is a custom software renderer, not Three.js or WebGL. Browser DOM, Canvas,
WebGL, and SVG elements are not provided by the current host. Three.js would need
an adapted CPU renderer for this project. SVG would need a CPU rasterization or
terminal drawing adapter. React hooks and composition work without those browser
APIs, but libraries that depend on them cannot run unchanged.

Run `zig build test-lab` for PTY cleanup checks. `zig build test` includes scene
and control checks using the real QuickJS and native-image bridge.

## Live JavaScript

Run `zig build run -- --live` for example 06. This starts one React page in one
QuickJS context, with no external components initially loaded.

- **Space** increments the host counter.
- **1** reads and evaluates `examples/live/counter.js`.
- **2** reads and evaluates `examples/live/clock.js`, adding a second component.
- **R** reloads the selected file in place.
- **C** clears loaded components and turns watching off, keeping the host counter.
- **W** toggles watching the selected file, checking content every half second.
- **Q** exits.

Edit either file while the app runs. No rebuild is required for these files.
For another source directory, run `quicktui --live /path/to/directory` with
`counter.js` and `clock.js` there. Paths are relative to the working directory
unless an absolute directory is passed.

External files are plain JavaScript, evaluated as function bodies with
`React`, `h = React.createElement`, and `api` supplied. They do not need to
bundle React again. For example:

```js
api.register("greeting", {
  title: "Added at runtime",
  render: () => h("text", { fg: "#85ddca" }, "Hello from a newly loaded file")
});
```

Each file owns its registered component IDs. A successful reload replaces that
file's registrations, removes any it no longer declares, and leaves other files
alone. The host stays mounted. Replaced components remount, resetting their
local hook state and cleaning up their effects. This is runtime component
replacement, not React Fast Refresh or automatic state migration.

Registration changes are staged until evaluation succeeds. Syntax errors and
synchronous evaluation errors preserve the previous registrations. A React
error boundary isolates a failing component and allows a later reload to fix it.
Registration staging does not roll back arbitrary side effects performed by a
script. Put timers and subscriptions in effects with cleanup functions.

The Zig loader reads UTF-8 files smaller than 1 MiB on a worker thread and
delivers source through the binary message interface. Evaluation runs in the
existing UI context. These are trusted application scripts with the same host
access as the rest of the JS app; this is not an untrusted-code sandbox. JSX,
ES module imports, and Node APIs need an external bundling step.

`zig build test` checks same-page updates, retained host state, and error
recovery. `zig build test-live` checks actual file edits, atomic-save watching,
and terminal cleanup using disposable files in `/tmp`.

## Shared JavaScript bundle

`js/examples.ts` selects the demo and `scripts/bundle.ts` builds one dependency
graph into `src/examples.js`. React, the reconciler, OpenTUI, and utility packages
are included once. The native executable embeds that bundle once and passes the
selected example name to the host. Lazy module initializers start only the chosen
demo; the smoke check also reuses the same React modules.

The matching macOS arm64 ReleaseSmall builds measured 10,273,000 bytes before
sharing and 7,909,064 bytes after sharing. JS remains unminified, and dragon assets
are unchanged.

There are no runtime JS files to install. Regenerating the bundle checks that
React, its reconciler, and the native-library adapter each occur once.

## Implementation

- `src/main.zig` selects the interactive example or headless checks.
- `src/app_host.c` owns the QuickJS runtime and POSIX terminal loop. It services input, resize signals, timers, and bounded batches of promise jobs, then sleeps in `poll` when idle. A self-pipe prevents lost signal wakeups.
- `js/counter.tsx` supplies the React application and a minimal OpenTUI render context. OpenTUI's root render traversal determines layout and drawing after a dirty notification.
- `js/platform/` provides the restricted component catalogue, scheduling and UTF-8 adapters, and native registry interface.
- `src/native_bridge.c` handles pointers and fixed callback registrations. `src/native_generated.c` contains the selected native wrappers.
- `scripts/bundle.ts` adapts upstream runtime imports at bundle time. The upstream React host configuration and box/text implementations remain in use.
- `vendor/` contains pinned sources, npm packages, licenses, and provenance.

See [the binding contract](js/platform/README.md) and
[dependency provenance](vendor/README.md).

## Current scope

The three examples demonstrate the complete built-in React widget catalogue:
boxes, styled text and links, images, input, textarea, select, tab-select,
scrollbox, ASCII fonts, code, line numbers, diff, and Markdown. The gallery also
registers the core slider and table widgets; scrollboxes demonstrate scrollbars.

The gallery adds single-widget text selection, focus traversal, bracketed paste,
cursor display, and native editing operations. Code blocks render as plain text;
the worker/WASM Tree-sitter syntax service is not enabled. Markdown formatting and
diff colors work independently of syntax highlighting. Embedded-terminal hosting
and application-specific filesystem/network services are not part of these demos.

The host implements the scheduling and UTF-8 facilities used by these examples,
not general Node/Bun compatibility. `process.nextTick` uses the QuickJS promise
queue. Native rendering and callbacks stay on the owning thread. This runtime
executes trusted bundled code and is not a sandbox.

The native library still includes the full upstream dependency set. Restricting
the JavaScript registry has not yet removed media and embedded-terminal code from
the native build. This runtime executes trusted bundled code and is not a sandbox.
QuickJS C sources compile without Zig's default C undefined-behavior instrumentation;
Zig code retains the checks selected by the optimization mode.

Herdr also requires `[experimental] kitty_graphics = true` in its config for
attached-client image rendering, followed by `herdr server reload-config`. A
successful capability reply alone does not prove that every enclosing multiplexer
will display the image.

## Poolside buffer views

The four terminal-buffer plane getters (`bufferGetCharPtr`, `bufferGetFgPtr`,
`bufferGetBgPtr`, and `bufferGetAttributesPtr`) keep their upstream symbol names,
but QuickTUI returns opaque native-backed JS objects instead of raw addresses.
Our FFI adapter routes these objects through `__readBufferView(view, offset,
length)`, which checks their Poolside generation and byte bounds before copying.
The Poolside token is held in native object storage, not a JS property.

Buffer resize/destruction revokes its views. Renderer resize/destruction
conservatively revokes all views, including views of standalone buffers; obtain
new views afterward. JS garbage collection releases registry entries, and host
teardown frees registry storage after JS finalizers run. The operation still
makes one copy into a JS ArrayBuffer, as the previous read path did.

This is a focused lifetime/bounds experiment, not an extension sandbox. Other
FFI operations still accept raw pointers, native buffer IDs are not scoped to
individual extensions, and all bridge operations remain on the UI thread.

Graphics lab: **[** steps rotation speed down and **]** steps it up, from −4×
through zero to +4×, with powers-of-two steps down to ±1/65,536×. This changes animation speed independently of the FPS target. Presets save
the speed; older presets use 1×. **R** restores 1× along with the scene controls.

Shape zoom in the graphics lab ranges from 0.3× to 8× using the scroll gesture.

Press **D** past Surface fractal to select **Surface fractal color**. It uses
the same black/ink coverage as the monochrome mode, with the lit dots tinted
by the shaded face hue. **C** changes palette; all terminal output modes support
the color variant. Faces retain the existing opaque depth-tested rendering.

**Surface fractal wash** is the next **D** mode. **Y/U** decreases/increases
wash strength by 5%, with 30% as the default. Zero reproduces monochrome pixels.
Projected faces, including hidden faces, contribute to a smoothed color field;
only the frontmost face determines the dither mask. Braille and glyph selection
retain the monochrome pattern. Presets include wash strength.

**Surface two-shade** follows wash in the **D** cycle. **H/L** lowers/raises
dark ink in 2.5% steps, from black to 50% brightness. Its default is 15%.
Only covered gaps receive dim color; lit dots keep the wash and exterior pixels
stay black. Braille/glyph output uses a dim character background, so boundaries
are approximated at character-cell resolution. **Y/U** still controls wash.
Presets include dark ink, and zero dark ink reproduces the wash mode.

Preset automatic names show the shape, tone, output/charset, and a ten-digit
hex settings fingerprint, for example `4D cube / Fractal wash / Braille #a09d317e52`.
The reusable `settingsHash` function includes pose and all saved settings, including
fine rotation, wash, dark ink, zoom, palette, brightness, contrast, and dot size.
It ignores viewport dimensions and the transport epoch. Identical settings have
the same fingerprint; this short hash is a label, not a collision-proof ID. The save form previews
the current automatic name. **A** selects automatic naming; **Tab** enters a
custom name. Automatic names refresh when you overwrite a slot, while custom
names remain custom. Existing files are only changed when you explicitly save.

The graphics lab also displays a live, reversible `QT1` settings code at the top
right. Click **[copy]** on its border to send the displayed code to the terminal
clipboard as one line, even though it wraps in the box. **[sent]** means the
OSC 52 request was sent; clipboard access depends on the terminal configuration.
The code changes with the current rendered pose.

`js/lab-settings-code.ts` exports `encodeSettings(scene, output, glyph)` and
`decodeSettings(code)`. The decoder returns a preset-shaped value for the lab
restore function. This adds the codec and copy UI; a paste/load-code UI is not
yet present. `QT1` fixes the rendering semantics and field schema. Fields use
URL-safe base64 separated by periods, with native f32/f64 precision. Empty or
missing trailing fields use permanent defaults, and new fields must be appended.
For example, `QT1` alone describes the default scene. Malformed fields, unknown
versions, and extensions beyond the decoder's known fields are rejected.
Viewport dimensions and message epochs are not encoded. Preset files and their
short name fingerprints remain separate from these reversible scene codes.
