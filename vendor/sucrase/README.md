# Sucrase

`sucrase.js` is Sucrase 3.35.1 and its bundled dependencies (licenses in
`LICENSE`), minified into one IIFE that sets `globalThis.__sucrase =
{ transform, version }`. QuickTUI's source-module loader evaluates it inside
QuickJS; see `docs/source-modules.md`.

Regenerate (needs npm once; nothing here runs at QuickTUI build time):

```sh
mkdir /tmp/sucrase-vendor && cd /tmp/sucrase-vendor
npm init -y && npm i sucrase@3.35.1 esbuild
printf 'import { transform, getVersion } from "sucrase";\nglobalThis.__sucrase = { transform, version: getVersion() };\n' > entry.js
npx esbuild entry.js --bundle --minify --format=iife --platform=neutral \
  --main-fields=module,main --legal-comments=none --outfile=sucrase.js
```

Changing this file changes the loader's cache salt, so cached bytecode is
rebuilt automatically.
