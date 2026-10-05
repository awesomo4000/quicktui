# Source modules

Source mode runs QuickTUI applications straight from `.ts`/`.tsx` files.
QuickJS loads ES modules natively; the loader adds resolution, the TypeScript
and JSX transform, CommonJS interop, and a bytecode cache. A module pack is
the same compiled graph in one file, for shipping without the sources. No Bun,
Node, or bundling step is involved in either.

```sh
# Any application entry, with no build step
./zig-out/bin/quicktui --run app.tsx
./zig-out/bin/quicktui --run app.tsx --self-test
# Ctrl+R re-reads edited sources; unchanged modules come from the cache
./zig-out/bin/quicktui --run app.tsx --reload

# The built-in demos and termpaint, from js/ instead of src/*.js
QUICKTUI_SOURCE=. ./zig-out/bin/quicktui --gallery
QUICKTUI_SOURCE=. ./zig-out/bin/termpaint

# Module packs: precompiled graphs that need no checkout at run time
./zig-out/bin/quicktui --build-pack app.pack app.tsx
./zig-out/bin/quicktui --run-pack app.pack [--reload] [--self-test]
QUICKTUI_PACK=examples.pack ./zig-out/bin/quicktui --gallery   # after --build-pack ... js/examples.ts --demo
zig build -Dmodule-pack=true   # embed the demo and termpaint packs instead of evaluating the bundles
```

Module packs are the default. `-Dmodule-pack=false` selects the legacy bundles.
The macOS integration checks below cover bundle, source, and pack modes.

## Pieces

| File | Role |
| --- | --- |
| `vendor/sucrase/sucrase.js` | Sucrase 3.35.1 (MIT), minified IIFE exposing `globalThis.__sucrase`. Strips types, lowers enums, converts JSX to the automatic runtime. No type checking. |
| `js/loader/policy.js` | Resolution, source patches, defines, and module kinds. A port of the `onResolve`/`onLoad` hooks in `scripts/bundle-app.ts`; keep the two in step. |
| `js/loader/cjs.js` | CommonJS runtime, evaluated in both realms. |
| `src/module_loader.c` | QuickJS glue: module hooks, the loader realm, compile and cache. |
| `src/modules.zig` | File reads, BLAKE3 hashing, the bytecode cache, configuration, `buildPack`/`enablePack`. |
| `src/pack_tool.zig` | `quicktui-pack`, the build-host tool that `zig build` runs to make packs. |

`policy.js` and `cjs.js` are plain JavaScript because they load before the
transform exists. All three JavaScript files are embedded in the executable.

## How a module loads

1. QuickJS calls the normalize hook with `(specifier, importer)`. The loader
   realm, a second `JSContext` in the application's runtime, runs
   `policy.resolve` and returns a canonical id: a `quicktui:/` library ID, an `app:/` application ID, or a
   `quicktui:*` virtual module.
2. The load hook calls `policy.key(id, mode)`. The cache key is
   BLAKE3(salt, mode, id, kind, patched source). The salt covers the QuickJS
   version, the pointer size, and the bytes of all three embedded loader files,
   so editing any of them invalidates the cache.
3. On a hit, `JS_ReadObject` loads the bytecode. On a miss, `policy.build`
   transforms the source and `JS_Eval(..., JS_EVAL_FLAG_COMPILE_ONLY)` compiles
   it, and the result is written to the cache.

Only strings cross between the two realms. Sucrase and the policy never share
objects with application code.

Sucrase keeps line numbers, so stack traces point at the original `.ts` lines
without source maps.

## Module kinds

| Kind | Chosen by | Loaded as |
| --- | --- | --- |
| `ts`, `tsx` | `.ts .mts .cts` / `.tsx .jsx` | Sucrase output |
| `esm` | `.mjs`, `"type": "module"`, or ES syntax in a `.js` | unchanged |
| `cjs` | `.cjs`, or a `.js` without ES syntax | facade over `cjs.js` |
| `text` | `.md .txt` | `export default "<contents>"` |
| `json` | `.json` | `export default <value>` |

## CommonJS

An `import` of a CommonJS package gets an ES module facade:

```js
const __m = globalThis.__quicktuiRequire(id);
export default (__m && __m.__esModule && "default" in __m) ? __m.default : __m;
const __e0 = __m["useState"]; /* ... */
export { __e0 as useState /* ... */ };
```

The facade needs export names when it is compiled. The loader realm executes
the package's CommonJS graph once to read its property names, then discards
the result. The compiled facade is cached under a key covering every source in
the package's static `require()` closure, so warm starts skip discovery. The application realm executes it again for real, in import order,
after bootstrap has installed timers and `process`. If discovery throws, the
loader falls back to a lexical scan for `exports.X =`.

Exports are bound when the facade evaluates. They are not live bindings, so a
property a package adds to `module.exports` later is not visible through a
named import.

`require()` inside an ES module (as in `js/examples.ts`) gets a module-scoped
`require`, inserted on the module's first line so line numbers are unchanged.
Requiring a CommonJS id executes it. Requiring an ES module evaluates its graph
synchronously and returns the namespace. A graph with top-level await is
rejected.

## Differences from the bundle

- Real ES module semantics: live bindings, and temporal dead zone (TDZ) errors
  in import cycles. The bundle's lazy initializers turned those TDZ errors into
  `undefined`. All current demos load without hitting one.
- Defines (`process.env.NODE_ENV`, `__SPRITE_FRAMES_BASE64__`, ...) are textual
  replacements made before the transform.
- Sucrase 3.35 redeclares the parameter when an enum member has the enum's own
  name (`enum Wrap { Wrap }`). `policy.js` renames that parameter after the
  transform.
- The loader has a cumulative 30-second policy/transform budget per UI runtime.
  This preserves the shorter UI preparation budget; Ctrl+C still interrupts.
  The build-host pack tool also has a 30-second execution deadline.
- `requestReload(source)` with an explicit bundle string still evaluates that
  string as a script. Without one, reload re-runs the module graph, which
  re-reads changed files.

## Module packs

A pack holds module bytecode, CommonJS wrapper bytecode, and the resolution
table (importer and specifier to id). Loading from a pack creates no loader
realm, runs no Sucrase, and reads nothing from disk, so it also starts faster
than evaluating the bundle: the vanilla demo self-test takes 0.04 s against
0.31 s.

`--build-pack` (or `quicktui-pack`) loads the entry's graph without
evaluating it, using `JS_ResolveModule`. It then follows every literal
`require("...")` in the recorded modules, because `js/examples.ts` selects
demos with `require()`. A dynamic `require(variable)` is not followed and fails
at run time with "not in the module pack". Paths matching `\.development\.js$`
(React's development builds, which `"production"` defines never select) are
left out. Function source text is stripped (`JS_STRIP_SOURCE`, as `qjsc` does by
default); line tables stay, for stack traces.

| Pack | Modules | CommonJS bodies | Edges | Size | Bundle size |
| --- | --- | --- | --- | --- | --- |
| `js/examples.ts --demo` | 140 | 14 | 378 | 3.36 MB | 3.83 MB |
| `js/termpaint-entry.ts` | 125 | 14 | 285 | 1.25 MB | 1.70 MB |
| `examples/consumer/app.tsx` | 121 | 14 | 275 | 1.18 MB | not measured |

The examples pack includes about 1.5 MB of base64 sprite frames.

The header records the QuickJS version and pointer size. A mismatched pack is
rejected rather than parsed. Bytecode is read with `JS_READ_OBJ_ROM_DATA`, so the
pack must stay mapped: `@embedFile` data, or `readPack`, which keeps the file
for the process lifetime. IDs use logical library/application roots in stack traces. Source imports outside
those roots are rejected. `--app-root` selects the application root, and
`addModulePack` uses the consumer build root automatically.

### Applications without Bun

```zig
// build.zig
const dep = b.dependency("quicktui", .{ .target = target, .optimize = optimize });
const pack = @import("quicktui").addModulePack(b, dep, b.path("app.tsx"));
exe.root_module.addAnonymousImport("app.pack", .{ .root_source_file = pack });

// main.zig
try quicktui.runPack(@embedFile("app.pack"), .{ .headless = self_test });
```

`addModulePack` runs `quicktui-pack` on the build host with a depfile, so
`zig build` rebuilds the pack only when a file it was built from changes.
`examples/consumer/app.tsx` built this way passes its self-test and the
interactive typing and paste check with the checkout removed.

## Cache

The cache directory is `$QUICKTUI_CACHE`, else `$XDG_CACHE_HOME/quicktui/modules`,
else `~/.cache/quicktui/modules`. Each entry is a magic header, the BLAKE3
digest of its payload, then QuickJS bytecode. Truncated or corrupted entries
fail the digest check and are rebuilt. Writes go to a temporary file and are
then renamed into place.

QuickJS bytecode is not safe to load from untrusted input. Keep the cache
directory writable only by the user who runs QuickTUI.

Set `QUICKTUI_TRACE_MODULES=1` to log each hit, miss, and uncached module to
stderr.

## Limits

- No type checking, as with Bun. Run `tsc --noEmit` separately if you want it.
- `const enum` across files, and TypeScript namespaces with values, depend on
  what Sucrase supports.
- Source mode reads library modules (`js/`, `vendor/`) from the checkout:
  `QUICKTUI_SOURCE`, or the build root baked into the executable. Packs have
  no such dependency.
- Application files must be below `--app-root` or the QuickTUI checkout.
  Without an explicit application root, the entry directory is used.

## Pack-only release builds

Development builds include the source loader by default. To compile it out:

```sh
zig build -Doptimize=ReleaseSmall -Dsource-loader=false
```

This also selects embedded demo packs by default. The resulting applications
contain the pack resolver and CommonJS runtime, but no filesystem module loader,
Sucrase, source-resolution policy, or disk bytecode cache. The build-host pack
compiler still reads the sources during the build; it is not installed by this
configuration. Module path environment overrides are ignored, and `--run`,
`--run-pack`, and `--build-pack` are unavailable in the resulting demo executable.
Pack builds no longer embed a redundant copy of the JavaScript bundle.

Library consumers pass `.@"source-loader" = false` in the dependency options,
then call `addModulePack` at build time and `runPack` at runtime. See
[the pack consumer](../examples/pack-consumer/README.md).

This removes filesystem **module loading**, not every native application feature.
The editor and paint examples still use their explicit native file services.
The live demo and explicit replacement-source reload APIs still evaluate supplied
JavaScript. Hosts that want a fixed-code application must also choose which of
those features they expose. Packs and bytecode caches are trusted build artifacts,
not safe containers for untrusted bytecode.

Source development is also a trusted operation: imports can read files, and
CommonJS export discovery executes dependencies in the loader context, which has
file-reading helpers. Building a pack does not evaluate the application's ES
module entry, but it can execute CommonJS dependencies during that discovery.

## Integration checks

```sh
zig build -Dmodule-pack=false  # compare against the legacy bundle path
python3 scripts/test-modules.py
python3 scripts/test-modules.py --embedded-only --bin-dir /path/to/pack-only/bin
python3 scripts/test-pack-consumer.py
```

The matrix uses Python timeouts and monotonic timing on macOS and Linux. Every
failure, including termpaint failures, contributes to its exit status. Test
artifacts and module caches stay in disposable temporary directories.

### macOS integration checkpoint, 10/04/2026

Verified on arm64 with Zig 0.16.0, ReleaseSmall:

- All 48 demo checks across bundle, cold source, warm source, and pack modes.
- Both independent source consumers and the packed React consumer.
- Embedded-only demos, smoke check, rejected loader CLI options, ignored source
  and pack-file environment overrides, and no module cache creation.
- A separate pack-only consumer, with its source removed and a real unpacked
  file present. Dynamic import rejected the unpacked file. The executable had
  no filesystem-loader/cache/build-pack symbols or application build path.
- The existing `zig build test` suite.
- `python3 scripts/test-source-reload.py`: edit source, Ctrl+R, updated text,
  preserved draft, and successful PTY shutdown.

The installed default macOS 27 SDK failed while Zig compiled libc++, with an
undefined `INFINITY`. These checks used the installed macOS 26.5 SDK instead.
`SDKROOT` alone did not change Zig's detected libc headers. A temporary libc
configuration supplied the matching include directories:

```sh
zig libc > /tmp/quicktui-libc.txt
# Edit include_dir and sys_include_dir in that temporary file to point to
# the compatible SDK's usr/include directory.
SDKROOT=/path/to/MacOSX26.5.sdk zig build -Doptimize=ReleaseSmall --libc /tmp/quicktui-libc.txt
# test-pack-consumer.py also accepts --libc /tmp/quicktui-libc.txt.
```

No system SDK selection or installed toolchain was modified. Interactive visual
checks of every demo remain to do. Linux results are recorded below.
Compilation budgets and application roots were added in the next integration pass.
CommonJS discovery remains a trusted build/development operation.

### Development without Bun

Default builds compile packs from the current TS/TSX sources. The ordinary React,
vanilla, and reload consumer examples now use `addModulePack` and `runPack`.
`test-paste` and the keyboard unit tests run the same 15 regression cases inside
QuickJS. `zig build bindings` uses Python; its generated ABI declarations and
metadata match the previous generator.

`quicktui --run src/app.tsx --app-root . --reload` lets the app import sibling
source directories. The low-level Zig module options also accept `app_root`;
the pack tool takes `--app-root`. None of these enable filesystem loading in a
`source-loader=false` executable.

`python3 scripts/test-module-edges.py` covers sibling imports, changed dependency
cache invalidation, corrupt cache recovery, import cycles, missing modules,
truncated pack framing, path leakage, and nonterminating CommonJS discovery.
All filesystem fixtures are temporary. It does not feed fabricated bytecode to
QuickJS; packs remain trusted artifacts.

Remaining Bun use is confined to the optional legacy bundler, its comparison
tests, and regeneration of that legacy output. These can be removed once the
pack workflow has had real consumer use; they are not part of normal builds,
source loading, input tests, or consumer builds.

### Linux integration, 10/04/2026

Verified on Linux x86-64 with glibc 2.39 and Zig 0.16.0:

```sh
zig build -j2 -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-gnu.2.39
zig build test -j2 -Doptimize=ReleaseSmall -Dtarget=x86_64-linux-gnu.2.39
```

The 48-case bundle/cold/warm/pack matrix passed, as did the updated default-pack
native/demo/input suite, module edge cases, and source-reload PTY check. Source
reload preserved the typed draft. The embedded-only release matrix also passed,
including ignored loader overrides, rejected loader CLI options, and no module
cache creation. The external pack-only consumer passed input/resize and missing
import checks with its source removed. Since the Linux release is stripped,
`check-pack-loader.py` separately inspects an unstripped loader object for
filesystem/cache/build-tool entry points and references. No Bun was needed for
these builds or tests.
An explicit GNU target was used to avoid the handoff's reported native glibc
header-discovery issue; native target autodetection and musl are not verified here.

The x86-64 Zig test server hung when native code wrote to its stdout protocol.
Native tests now use the stock test runner in standalone mode, with a Python
wrapper checking its exit code and enforcing a 180-second timeout. This path
passes on macOS too and preserves the stock runner's allocator leak checks.

### Package-resolution follow-up

Bare package imports search from the importing file before falling back to
vendored dependencies. Explicit QuickTUI aliases and React remain shared.
Consumer dependencies must still fit under the application root.
Package exports block unlisted paths; matching conditions follow declaration
order and wildcard matches prefer the most specific path. Export targets must
name files, without directory or extension fallback.

Run `python3 scripts/test-module-packages.py` for these fixtures, or add
`--compare-bun` for an optional browser-bundler comparison. The remaining
compatibility work is
tracked in [the integration checklist](../specs/module-loader-integration.md).

### Parser adapter

The loader uses the existing vendored Sucrase parser for define replacement and
literal `require()` discovery. It preserves strings, comments, regular expressions,
JSX text, and local bindings while handling expressions inside JSX and templates.
The small adapter source and regeneration instructions live in
`vendor/sucrase/entry.js` and `vendor/sucrase/README.md`. It uses pinned internal
Sucrase APIs; QuickJS itself is unchanged. Application code receives no new parser
or native capabilities, and pack-only releases omit the adapter with the loader.

`python3 scripts/test-module-syntax.py` checks both the adapter and actual
source/pack execution. Computed requires still need their target present in the
pack; they are not discovered automatically.

Selected unchanged Bun/esbuild fixtures also run through
`python3 scripts/test-bun-reference.py`. The pinned files, attribution, exact
coverage, and expected failures are documented in
[the reference README](../tests/reference/bun/README.md). Bun is needed only to
regenerate the selected fixture data, not to run these checks.
