# Vanilla JavaScript consumer

A standalone application using `quicktui/core` and `quicktui/widgets`, with no
React imports. It builds the same renderable tree the React adapter uses.

Try it in the main demo binary with `quicktui --vanilla`. That binary also bundles
the React demos, but this example uses only the core. The independent build
below excludes React entirely.

From the repository root:

```sh
bun scripts/bundle-app.ts examples/vanilla/app.ts examples/vanilla/app.js
cd examples/vanilla
zig build -Doptimize=ReleaseSmall
./zig-out/bin/consumer
```

Ctrl+K increments the counter. Ordinary typing goes to the focused input. Ctrl+C
exits. Use `--self-test` for the embedded headless checks, or run
`zig build test-vanilla -Doptimize=ReleaseSmall` from the repository root for an
independent build and PTY test.

Property changes schedule a frame automatically. The example also checks child
reordering/removal, subscription removal, and that key-up does not insert text.
See [the core API](../../docs/core-api.md) for lifecycle and adapter details.
