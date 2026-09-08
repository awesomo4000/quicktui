# Vendored dependencies

Normal Zig builds use local paths and the checked-in JavaScript bundle. They do
not fetch dependencies. Upstream license files remain beside their sources;
the generated JavaScript bundle includes the bundled packages' license texts.

| Directory | Source pin |
| --- | --- |
| `quickjs/` | QuickJS 2026-06-04, https://bellard.org/quickjs/quickjs-2026-06-04.tar.xz |
| `opentui/` | https://github.com/anomalyco/opentui, commit `7581976f4d2c917fd5ae5266c8bc61f0e44fc933`, core/React 0.5.10 |
| `opentui/packages/native/zig-deps/` | Extracted from that revision's `src/vendor/zig-deps.tar.gz` |
| `js/node_modules/` | Exact npm dependency tree in `js/package-lock.json`, installed with scripts disabled |

The native archive contains Yoga 3.2.1, Ghostty commit
`727b8a02f8734840de664c060678dd66f01931f6`, OpenTUI's uucode commit
`8ad04b756f85a5ba1ac8d2b8cb48d0946f06b630`, and Ghostty's uucode commit
`2826a37a4562284fdacd8fa029d49509cc9bffcd`. OpenTUI already vendors its image
and audio C dependencies under `packages/native/src/vendor/`. Their README files
and source headers record provenance and licenses.

JavaScript pins include React 19.2.3, react-reconciler 0.33.0, scheduler 0.27.0,
the OpenTUI core's declared dependencies and parser peer dependency, plus `events`
and `buffer` for later host adaptation. Optional React developer tools and platform
OpenTUI binary packages are not included. The native library builds from source.

## Local changes

`opentui-quicktui.patch` records local changes against the pinned OpenTUI source:

- Add the `quicktui-static` build option, exposing the full native ABI as a static library without configuring unrelated upstream build artifacts.
- Include extracted `zig-deps` in the native package's distributable paths.
- Stop ignoring the extracted dependency directory in version control.
- Use virtual Kitty placements and Unicode placeholder cells under tmux so pane redraws preserve images. The standard diacritic table matches the vendored Ghostty decoder.

QuickTUI also bounds OpenTUI parser paste retention to 1 MiB by default and ignores empty transport chunks. See `opentui-input.patch` for this input-parser adaptation.

QuickJS and the npm package sources are unmodified. OpenTUI's native dependency
archive already contains upstream integration patches and reduced build scripts;
QuickTUI uses those as shipped in the pinned archive.

The interactive counter also applies build-time JavaScript adaptations in
`scripts/bundle.ts`. These replace runtime discovery and broad catalogues
without editing the vendored files. See `js/platform/README.md` for the binding
and storage contracts. Its generated bundle includes the bundled JavaScript
packages' license texts and OpenTUI's license.

## Source archive SHA-256

```text
b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a  quickjs-2026-06-04.tar.xz
fe3429d4359d9689a6f1225cb50b14769c8f84fe98ede470b72418027adb7368  opentui-7581976f4d2c917fd5ae5266c8bc61f0e44fc933.tar.gz
41df74dc52ec226e9610a2462054fab33e918ea950750f98d6cc0e26b0e9e04b  opentui/packages/native/src/vendor/zig-deps.tar.gz
```

To update OpenTUI, fetch a reviewed source revision, reapply or adapt the recorded
patch, and extract its native dependency archive. To update JavaScript packages,
change the exact versions in `js/package.json`, regenerate the npm lockfile with
scripts disabled, and include the resulting package files. Regenerate `src/examples.js`
with `zig build bundle`, then run `zig build test` and rebuild both target artifacts.

## Poolside

Poolside 0.2.0 supplies the generational registry for terminal-buffer read views.
The four Zig source files, README, and MPL-2.0 license are vendored in
`poolside/`; see [provenance](poolside/PROVENANCE.md). Sources are unmodified.
