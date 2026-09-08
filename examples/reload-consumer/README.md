# Independent reload application

This example uses only the public `quicktui` JS exports and Zig module.
It preserves draft text across fresh runtimes. Caret/selection restoration is
left to the application and is not demonstrated here.

From this directory:

```sh
bun ../../scripts/bundle-app.ts app.tsx app.js
zig build -Doptimize=ReleaseSmall
./zig-out/bin/consumer
```

Type a draft, press Ctrl+R to replace the runtime, and Ctrl+C to quit.
The native caller explicitly opts in with `.reload = true`. See
[the application API](../../docs/application-api.md) for limits and lifecycle rules.
