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
with fading verbs and oscillating values. It runs independently of native jobs.
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
