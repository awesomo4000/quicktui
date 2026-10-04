# Independent application example

This app imports `react`, `quicktui`, and `quicktui/testing`. The build-host pack tool supplies
React and the host adaptations. It does not copy QuickTUI internals.

From this directory:

```sh
zig build -Doptimize=ReleaseSmall
./zig-out/bin/consumer
./zig-out/bin/consumer --self-test
```

To move the app elsewhere, update the QuickTUI dependency path in build.zig.zon
only. Zig dependency paths are relative to the consumer.
The library is the dependency's `quicktui` module.

`zig build test-consumer` from the QuickTUI checkout copies this example to a
disposable directory, builds a module pack from that directory, builds, and runs both headless
and real PTY checks. The tests do not need a running Herdr or tmux session.

See [the application contract](../../docs/application-api.md).

The build uses Zig and the embedded QuickJS transpiler; Bun is not required.
The executable has filesystem module loading disabled.
