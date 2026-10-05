# Sucrase

`sucrase.js` contains Sucrase 3.35.1 and its bundled dependencies, with licenses
in `LICENSE`. The maintained `entry.js` adapter exposes `transform`, `version`,
`rewriteDefines`, and `inspectRequires` as `globalThis.__sucrase` in the trusted
loader realm. These helpers are not installed in application JavaScript, and
pack-only releases exclude this bundle.

The adapter imports Sucrase's internal parser and shadowed-global analysis.
It adds module-level binding detection, including imports, and normalizes escaped
identifier names. Defines replace free identifier/dotted reads, preserving text,
comments, and line breaks. Object shorthand keeps its original key. Literal
require discovery ignores locally bound names and member calls, and decodes
parser-validated string tokens using the JS engine. Computed requires are not
statically discovered. This is a version-pinned adapter, not an upstream API;
run the syntax fixtures when upgrading Sucrase.

Regenerate from the project root. npm and esbuild are maintenance tools only;
normal builds consume the checked-in bundle:

```sh
work=$(mktemp -d /tmp/quicktui-sucrase.XXXXXX)
npm install --prefix "$work" --ignore-scripts --no-audit --no-fund \
  sucrase@3.35.1 esbuild@0.25.0
cp vendor/sucrase/entry.js "$work/entry.js"
"$work/node_modules/.bin/esbuild" "$work/entry.js" \
  --bundle --minify --format=iife --platform=neutral \
  --main-fields=module,main --legal-comments=none \
  --outfile=vendor/sucrase/sucrase.js
```

Changing the bundle changes the loader cache salt, so cached bytecode is rebuilt.
After rebuilding QuickTUI, run `python3 scripts/test-module-syntax.py`. It tests
both actual source/pack behavior and the adapter directly inside QuickJS, with
all fixture files in a disposable `/tmp` directory.
