# Module loader integration checklist

The goal is a Bun-free development and distribution workflow for QuickTUI,
with a documented module subset. QuickJS remains the runtime. This is not a
Node or Bun compatibility project, and source loading is trusted development
work. Packs and bytecode caches are trusted artifacts too.

## Completed verification

- [x] Default builds and consumers use embedded module packs.
- [x] Pack-only releases compile out filesystem module loading.
- [x] Demo matrix, source reload, and retained input on macOS and Linux glibc.
- [x] Changed source dependencies and corrupt cache recovery.
- [x] ES module cycles, missing imports, malformed pack framing, compile budgets.
- [x] Consumer-local and scoped packages; shared React remains library-owned.
- [x] Explicitly blocked and missing exports do not fall back to physical files.
- [x] Export conditions respect declaration order; specific wildcard paths win.
- [x] Selected export targets must name existing files within the package.
- [x] Package fixtures in cold/warm source and pack modes, with optional Bun
  browser-bundle comparison. Run `python3 scripts/test-module-packages.py`;
  append `--compare-bun` when Bun is installed.

The package fixtures passed on macOS and Linux x86-64 glibc on 10/05/2026.
The optional Bun comparison and full QuickTUI test suite also passed on macOS.

## Source rewriting

- [x] Replace regex defines with token/scope-aware replacement. Preserve strings,
  comments, regex literals, template text, property names, and shadowed locals.
- [x] Apply defines inside template expressions and JSX expressions correctly.
- [x] Replace regex `require()` discovery; decode escaped literal specifiers and
  distinguish real calls from text, property calls, and shadowed functions.
- [x] Copy pinned Bun/esbuild reference files with attribution and run a selected
  ten-case subset. See `tests/reference/bun/README.md` for coverage and two
  expected failures. The define regression exposed and fixed a statement-joining
  bug in identifier/member replacements.
- [ ] Expand reference coverage to shadowing, CommonJS interop, and source locations.

The adapter is maintained in `vendor/sucrase/entry.js` against Sucrase 3.35.1.
Run `python3 scripts/test-module-syntax.py` after rebuilding. Its fixtures run
inside QuickJS in cold/warm source and packed modes. These passed on macOS
and Linux x86-64 glibc on 10/05/2026. The full macOS suite and the cache/error-path
fixtures passed with the new adapter too.

## Remaining module semantics

- [ ] Separate import/require condition sets. The current loader selects the
  browser/import/module/default profile for both.
- [ ] Export arrays with invalid alternatives, invalid/mixed export objects,
  encoded targets, and package self references.
- [ ] `package.json` imports, browser field remapping, and tsconfig path aliases:
  decide supported behavior and fail clearly for unsupported configurations.
- [ ] Directory probing cycles, packages without metadata, symlink identity,
  and packages outside the explicit application root.
- [ ] CJS cycles, late exports, getters, discovery side effects, conditional
  exports, and CJS/ESM interop including top-level await.
- [ ] Dynamic import and computed require: document exactly what enters a pack.
- [ ] Replace remaining regex-based ESM classification, CJS export-name fallback,
  and the narrow Sucrase enum workaround where needed.
- [ ] Define edge semantics for assignments, optional/computed member access,
  direct eval/with scopes, statement boundaries for non-identifier replacement
  expressions, and TypeScript import-equals require discovery.
- [ ] TypeScript enums/namespaces, extension probing, JSX configuration, and
  type-only import fixtures.

## Build and runtime robustness

- [ ] Package metadata changes invalidate the right cached results and Zig builds.
- [ ] New dependencies and assets trigger incremental pack rebuilds.
- [ ] Concurrent cache writers, interrupted writes, and read-only cache directories.
- [ ] Transform diagnostics and runtime stack locations in source and pack modes.
- [ ] Repeated reloads with pending jobs, failures, and resource accounting.
- [ ] Linux native target autodetection and musl.
- [ ] Real consumer app use before deleting the optional legacy Bun path.

## References and intentional differences

Bun currently implements its resolver and parser in Rust. The reviewed reference
is its [package metadata parser](https://github.com/oven-sh/bun/blob/main/src/resolver/package_json.rs),
including distinct exports/imports and browser-map handling. The
[resolver directory](https://github.com/oven-sh/bun/tree/main/src/resolver) and
[JavaScript parser](https://github.com/oven-sh/bun/tree/main/src/js_parser) are
references for subsequent work. No Bun runtime implementation was copied.
Pinned upstream tests are now copied under `tests/reference/bun`, with provenance
and licenses; the selected runner does not depend on Bun.

The behavioral comparison uses the installed Bun browser bundler directly, not
QuickTUI's legacy plugin, which also pins generic package lookup to vendor/js.
It checks expected values and success/failure, not identical diagnostics.
QuickTUI currently treats `exports: null` at the package root as blocked and
conservatively rejects percent-encoded/backslash export targets. These cases
are not claims of complete Bun/Node resolution compatibility.
