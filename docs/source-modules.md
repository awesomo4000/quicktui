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

The prebuilt bundles remain the default. Every self-test passes in bundle,
source, and pack modes.

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
   `policy.resolve` and returns a canonical id: an absolute path, or a
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
- The host's preparation deadline (06b reload) is paused while modules compile;
  Ctrl+C still interrupts.
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
for the process lifetime. Ids are absolute paths on the build machine; they
appear in stack traces.

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
- `-Dmodule-pack=true` still embeds `src/examples.js` too, which `--smoke` and
  the bundle code paths use.
