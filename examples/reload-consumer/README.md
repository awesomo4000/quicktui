# Independent reload application

This example uses only the public `quicktui` JS exports and Zig module.
It preserves draft text, caret, and selection across fresh runtimes. The example
uses native editor offsets directly rather than converting them to JS string indices.

From this directory:

```sh
bun ../../scripts/bundle-app.ts app.tsx app.js
zig build -Doptimize=ReleaseSmall
./zig-out/bin/consumer
```

Type a draft, press Ctrl+R to replace the runtime, and Ctrl+C to quit.
The native caller explicitly opts in with `.reload = true`. See
[the application API](../../docs/application-api.md) for limits and lifecycle rules.
