# Bun test references

These three test files are copied unchanged from
[Bun revision 9bd19c98eacc01530a4e7609bc427abffa87d77e](https://github.com/oven-sh/bun/tree/9bd19c98eacc01530a4e7609bc427abffa87d77e/test/bundler):

- `upstream/esbuild/default.test.ts`
- `upstream/esbuild/packagejson.test.ts`
- `upstream/bundler_cjs2esm.test.ts`

Credit to the Bun contributors. Bun identifies its own code as MIT-licensed;
its unmodified license document is included as `LICENSE.md`. The two files
under `esbuild/` explicitly identify their origin in Evan Wallace's esbuild
test suite. Its MIT license, copyright 2020 Evan Wallace, is included as
`LICENSE.esbuild`, taken from the esbuild 0.25.0 package. Original source
comments and attribution are preserved.

## What runs here

`zig build test-loader-contract` runs these reference checks alongside the
application import contract, using fresh build artifacts.
`python3 scripts/test-bun-reference.py` runs ten selected cases using the checked-in
`fixtures.json`. Normal testing does not require Bun, npm, or a network connection.
The runner verifies SHA-256 hashes of the copied files. The rest of the upstream
suite is reference material, not claimed coverage. The CommonJS file is included
for the next set of interoperability tests; none of its cases run yet.

| Upstream case | QuickTUI check |
| --- | --- |
| ExportsImportOverRequire | deliberate rejection of external require conditions |
| ExportsDefaultOverImportAndRequire | deliberate rejection of external require conditions |
| ExportsBrowser | source + pack output |
| ExportsRequireOverImport | deliberate rejection of application CommonJS |
| ExportsErrorPackagePathNotExported | source + pack-build rejection |
| ExportsErrorModuleNotFound | source + pack-build rejection |
| ExportsErrorUnsupportedDirectoryImport | source + pack-build rejection |
| ExportsNoConditionsMatch | source + pack-build rejection |
| DefineInfiniteLoopESBuildIssue2407 | parser adapter execution in source + pack |
| DefineOptionalChain | expected failure: optional/computed access; also upstream TODO |

The runner keeps fixture program text and expected stdout unchanged. It remaps
all synthetic absolute paths beneath a fresh disposable `/tmp` directory. It
installs a console capture and minimal QuickTUI self-test wrapper. Error cases
check rejection and our error category, not Bun-specific diagnostic wording.
Define tests call our adapter directly because their custom define maps are not
part of the public QuickTUI source CLI. For those two cases, the upstream runtime
setup runs first and its import of the generated output is replaced by evaluation
of our transformed fixture. They test replacement behavior, not Bun minification
or output formatting.

Expected failures are checked in both source and packed execution. An unexpected
pass fails the runner too, requiring us to update this coverage record.

Verified on macOS and Linux x86-64 glibc on 10/05/2026: eight cases passed,
two matched the documented expected failures. The full macOS QuickTUI suite
and syntax fixtures also passed after the identifier-replacement fix.

## Updating

Keep upstream files unchanged. To regenerate only the selected fixture data:

```sh
python3 scripts/extract-bun-reference.py
```

This maintenance command requires Bun to evaluate the selected self-contained
object literals. It does not execute the full upstream suite. Its explicit case
list and pinned revision should be reviewed whenever updating the reference.
Do not silently add or execute arbitrary upstream fixtures; inspect their file
operations and remap all paths into the temporary test directory first.

On 10/06/2026 the supported contract was narrowed to application ES imports.
The three import/require-condition cases now assert explicit source/pack-build
rejection instead of upstream behavior. They are counted as contract checks,
not Bun compatibility passes. Only DefineOptionalChain remains an expected
failure. The original fixture data and copied upstream files are unchanged.
