# Embedded-pack consumer

This application builds its TSX entry with QuickTUI's build-host pack tool.
Bun and Node are not needed. The executable embeds the compiled module graph
and links QuickTUI with `source-loader = false`.

```sh
zig build -Doptimize=ReleaseSmall
./zig-out/bin/consumer
./zig-out/bin/consumer --self-test
```

See `build.zig` for `addModulePack` and `main.zig` for `runPack`. The consumer
has no filesystem module loader, transpiler, or disk module cache. Source/pack
path environment overrides have no effect. Native host capabilities remain
under the application's control; this option is not a general JS sandbox.

From the repository root, `python3 scripts/test-pack-consumer.py` builds a
copy in a temporary directory, removes its TSX source, checks input behavior
and missing-import rejection, and inspects the binary for loader symbols.
