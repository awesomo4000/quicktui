# Counter binding contract

`symbols.json` is the counter profile's allowlist. `bindings.json` records the
FFI declaration, checked native argument and return types, and source location
for each of its 247 functions. `scripts/generate-bindings.ts` refuses unknown
native types and signature mismatches, then writes fixed C calls. Pointer-taking
arguments use the platform C pointer ABI; native object handles remain `u32`.

The allowlist comes from tracing mount, rendering, updates, resize, and teardown,
plus terminal setup/replies, native Unicode encoding, native images, and mouse hit testing. It excludes file access, native output feeds, and worker APIs.

The gallery enables the upstream text/edit-buffer operation families, framebuffers,
selection, cursor controls, and Yoga measurement callbacks. Text/edit buffers retain
their encoded JavaScript arrays while native memory registrations borrow them; the
upstream owner releases these registrations before discarding the arrays.

## Storage ownership

- Numeric handles identify native objects. Actual addresses use BigInt, with null or zero reserved for a null pointer. The bridge does not convert nonzero JavaScript numbers to addresses.
- Typed-array arguments borrow their backing storage for the synchronous native call. The bridge accounts for byte offsets. Call arguments keep the storage alive until the call returns.
- `bun-ffi-structs` retains pointed-to string/color storage through its packed owner buffer using WeakMaps. The selected styled-text operation copies text into native storage before returning. Color setters also copy their values.
- Output structs borrow writable JavaScript buffers during the call. Native layout output consists of six consecutive `f32` fields. Styled chunks use the upstream 64-bit C layout: pointer, size, two color pointers, `u32` attributes, padding, link pointer, size.
- `toArrayBuffer` copies native bytes into new JavaScript storage. No JavaScript read view remains attached to a freed native allocation.
- `encodeUnicode` returns a native allocation. The width adapter reads its encoded cells and calls `freeUnicode` in a `finally` block.
- Native handles are destroyed during React unmount and render-tree cleanup, before destroying the renderer and disposing its library wrapper.
- The demo decodes the embedded `assets/dragon.jpg` into native storage. The vendored OpenTUI license covers the example asset. The image renderable retains its own native reference; unmount releases it, then shutdown releases the sample's original reference.

These are internal interfaces for trusted code. They do not validate arbitrary
addresses or establish a memory-isolation boundary. Byte offsets and native
signatures are checked, but callers remain responsible for matching buffer
lengths and the selected native operations' contracts.

## Callbacks and shutdown

One QuickJS runtime owns four fixed callback slots: logging, events, Yoga measure,
and Yoga dirtied. Callback JavaScript values stay rooted until explicit disposal.
Callbacks enter QuickJS only on its owning thread. Cross-thread callbacks are not
supported; the counter cannot enable native threaded rendering or custom feeds.

Synchronous callback exceptions are captured and rethrown after the native call
returns. Upstream disposal unregisters callback producers before the bridge frees
its callback roots. The host disables interruption during shutdown so React can
unmount with native resources still available. It restores terminal modes and
prints buffered diagnostics even when initialization or rendering throws.

## Bundle adaptations

The build replaces OpenTUI's FFI backend, native-library discovery, runtime helper,
and broad component/lib catalogues. It keeps the existing React host configuration,
property updates, text modifiers, box/text classes, root layout/render traversal,
and input parser. The real upstream image renderable is included for native-image
sources. Unsupported component classes in guarded upstream branches
throw if constructed and are never included in the catalogue.

For `bun-ffi-structs`, only backend discovery is replaced. Its packing and retention
implementation stays intact. UTF-8 codecs use vendored Buffer, timers use a
monotonic host clock, and promise jobs implement microtasks. Unsupported filesystem
and runtime-asset operations fail explicitly.

## Graphics negotiation

Terminal identity, including `TMUX`, is passed through `setTerminalEnvVar` before
`setupTerminal`. OpenTUI supplies the tmux DCS wrapper for both the probe and pixel
commands. Passthrough being disabled therefore drops the wrapped probe rather
than treating its APC content as a title.

The input adapter reads response events from their `sequence` property. Only an
APC response with image ID 31337 and status `OK` enables pixel rendering. Other
IDs cannot enable it; errors or a two-second timeout retain the block fallback.
The application does not infer success from `TERM_PROGRAM`, send unwrapped
retries through tmux, or enable file/shared-memory image transports.

Under tmux, the native renderer creates virtual Kitty placements and emits
Unicode placeholders as ordinary text. Each cell carries the image ID, placement
ID, row, and column, so tmux can retain it across redraws and clipping. Placements
larger than the protocol diacritic table use block fallback.

## Gallery profile

`gallery-core.ts` and `gallery-catalogue.ts` expose the full built-in React widget
catalogue plus slider and table. The first two examples retain their smaller
catalogue. The gallery uses upstream keyboard events, widget focus subscriptions,
and selection conversion; selection is confined to its initiating widget.

`plain-code.ts` uses Marked tokens to supply Markdown style/conceal captures and
returns no captures for programming-language code. It does not claim Tree-sitter
support or launch workers. The bundler adapts only the POSIX
basename lookup in the filetype resolver. Diff and Marked licenses are embedded
alongside the other bundled package licenses.

The host supports synchronous or promise-returning example self-tests, with a
bounded job/frame loop. Gallery checks traverse all pages and exercise real parser
bytes against React state and native cell buffers.
