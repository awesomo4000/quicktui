# Independent application example

This app imports `react`, `quicktui`, and `quicktui/testing`. The bundler supplies
React and the host adaptations. It does not copy QuickTUI internals.

From this directory:

```sh
bun ../../scripts/bundle-app.ts app.tsx app.js
zig build -Doptimize=ReleaseSmall
./zig-out/bin/consumer
./zig-out/bin/consumer --self-test
```

To move the app elsewhere, update the QuickTUI dependency path in build.zig.zon
and the bundler command. Zig dependency paths are relative to the consumer.
The library is the dependency's `quicktui` module.

`zig build test-consumer` from the QuickTUI checkout copies this example to a
disposable directory, bundles from that directory, builds, and runs both headless
and real PTY checks. The tests do not need a running Herdr or tmux session.

See [the application contract](../../docs/application-api.md).
