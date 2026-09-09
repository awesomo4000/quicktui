const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    switch (target.result.os.tag) {
        .macos, .linux => {},
        else => @panic("QuickTUI currently supports macOS and Linux"),
    }
    switch (target.result.cpu.arch) {
        .aarch64, .x86_64 => {},
        else => @panic("QuickTUI's native ABI currently requires aarch64 or x86_64"),
    }
    const native = b.dependency("opentui", .{
        .target = target,
        .optimize = optimize,
        .@"quicktui-static" = true,
    }).artifact("opentui");

    const quickjs_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    quickjs_module.addIncludePath(b.path("vendor/quickjs"));
    quickjs_module.addCSourceFiles(.{
        .root = b.path("vendor/quickjs"),
        .files = &.{ "quickjs.c", "dtoa.c", "libregexp.c", "libunicode.c", "cutils.c" },
        .flags = &.{ "-std=gnu11", "-D_GNU_SOURCE", "-DCONFIG_VERSION=\"2026-06-04\"", "-fno-sanitize=undefined" },
    });
    const quickjs = b.addLibrary(.{ .name = "quickjs", .linkage = .static, .root_module = quickjs_module });

    const runtime = b.addModule("quicktui", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const poolside = b.createModule(.{ .root_source_file = b.path("vendor/poolside/src/root.zig") });
    runtime.addImport("poolside", poolside);
    runtime.addIncludePath(b.path("vendor/quickjs"));
    runtime.addCSourceFile(.{ .file = b.path("src/quickjs_bridge.c"), .flags = &.{"-std=c11"} });
    runtime.addCSourceFiles(.{ .files = &.{ "src/native_bridge.c", "src/native_generated.c", "src/app_host.c", "src/endpoint_tests.c" }, .flags = &.{"-std=c11"} });
    runtime.linkLibrary(quickjs);
    runtime.linkLibrary(native);

    const exe = b.addExecutable(.{
        .name = "quicktui",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "quicktui", .module = runtime }},
        }),
    });
    b.installArtifact(exe);
    const paint = b.addExecutable(.{
        .name = "termpaint",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/termpaint.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "quicktui", .module = runtime }},
        }),
    });
    b.installArtifact(paint);
    b.getInstallStep().dependOn(&b.addInstallDirectory(.{ .source_dir = b.path("skills"), .install_dir = .prefix, .install_subdir = "share/termpaint/skills" }).step);
    const paint_run = b.addRunArtifact(paint);
    if (b.args) |args| paint_run.addArgs(args);
    b.step("termpaint", "Run the standalone paint application").dependOn(&paint_run.step);

    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run the interactive React / QuickJS / OpenTUI counter").dependOn(&run.step);

    const tests = b.addTest(.{ .root_module = runtime });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Test JavaScript evaluation, jobs, errors, and native ABI calls");
    test_step.dependOn(&run_tests.step);
    for ([_][]const u8{ "--game-self-test", "--keyboard-self-test" }) |flag| {
        const game_test = b.addRunArtifact(exe);
        game_test.addArg(flag);
        test_step.dependOn(&game_test.step);
    }
    const paint_test = b.addRunArtifact(paint);
    paint_test.addArg("--self-test");
    test_step.dependOn(&paint_test.step);
    const self_test = b.addRunArtifact(exe);
    self_test.addArg("--self-test");
    test_step.dependOn(&self_test.step);

    const smoke_test = b.addRunArtifact(exe);
    smoke_test.addArg("--smoke");
    test_step.dependOn(&smoke_test.step);
    const gallery_test = b.addRunArtifact(exe);
    gallery_test.addArg("--gallery-self-test");
    test_step.dependOn(&gallery_test.step);
    const reload_test = b.addRunArtifact(exe);
    reload_test.addArg("--reload-self-test");
    test_step.dependOn(&reload_test.step);
    const live_test = b.addRunArtifact(exe);
    live_test.addArg("--live-self-test");
    test_step.dependOn(&live_test.step);
    const lab_test = b.addRunArtifact(exe);
    lab_test.addArg("--lab-self-test");
    test_step.dependOn(&lab_test.step);
    const lab_native_test = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/examples/lab_worker.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "quicktui", .module = runtime }},
    }) });
    const lab_native_run = b.addRunArtifact(lab_native_test);
    test_step.dependOn(&lab_native_run.step);
    const editor_worker_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/examples/editor_worker.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "quicktui", .module = runtime }},
    }) });
    test_step.dependOn(&b.addRunArtifact(editor_worker_tests).step);
    const editor_test = b.addRunArtifact(exe);
    editor_test.addArg("--editor-self-test");
    test_step.dependOn(&editor_test.step);
    const messages_test = b.addRunArtifact(exe);
    messages_test.addArg("--messages-self-test");
    test_step.dependOn(&messages_test.step);
    const worker_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/examples/message_worker.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "quicktui", .module = runtime }},
    }) });
    const run_worker_tests = b.addRunArtifact(worker_tests);
    test_step.dependOn(&run_worker_tests.step);
    const mouse_test = b.addRunArtifact(exe);
    mouse_test.addArg("--mouse-self-test");
    test_step.dependOn(&mouse_test.step);

    const endpoint_terminal = b.addExecutable(.{
        .name = "endpoint-terminal-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/endpoint_terminal_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "quicktui", .module = runtime }},
        }),
    });
    // Import the module so its C host objects participate in linking.
    const endpoint_pty = b.addSystemCommand(&.{ "python3", "scripts/test-endpoint-terminal.py" });
    endpoint_pty.addArtifactArg(endpoint_terminal);
    b.step("test-endpoint-terminal", "Stress input, resize, disconnect and quit under message flood").dependOn(&endpoint_pty.step);
    const consumer_test = b.addSystemCommand(&.{ "python3", "scripts/test-consumer.py" });
    b.step("test-consumer", "Build and run an external consumer, requires Bun and Python").dependOn(&consumer_test.step);
    const bundler_test = b.addSystemCommand(&.{ "bun", "test", "tests/bundler.test.ts" });
    b.step("test-bundler", "Check consumer imports and source maps, requires Bun").dependOn(&bundler_test.step);
    const paste_test = b.addSystemCommand(&.{ "bun", "test", "tests/paste.test.ts" });
    b.step("test-paste", "Exercise fragmented and oversized paste input, requires Bun").dependOn(&paste_test.step);

    const failure_test = b.addExecutable(.{
        .name = "quicktui-failure-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/failure_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "quicktui", .module = runtime }},
        }),
    });
    const terminal_test = b.addSystemCommand(&.{ "python3", "scripts/test-terminal.py" });
    terminal_test.setCwd(b.path("."));
    terminal_test.addArtifactArg(exe);
    terminal_test.addArtifactArg(failure_test);
    b.step("test-terminal", "Check terminal restoration in disposable PTYs, requires Python 3").dependOn(&terminal_test.step);
    const mouse_terminal_test = b.addSystemCommand(&.{ "python3", "scripts/test-mouse.py" });
    mouse_terminal_test.setCwd(b.path("."));
    mouse_terminal_test.addArtifactArg(exe);
    b.step("test-mouse", "Check mouse reporting and cleanup in disposable PTYs").dependOn(&mouse_terminal_test.step);
    const gallery_terminal_test = b.addSystemCommand(&.{ "python3", "scripts/test-mouse.py" });
    gallery_terminal_test.setCwd(b.path("."));
    gallery_terminal_test.addArtifactArg(exe);
    gallery_terminal_test.addArg("--gallery");
    b.step("test-gallery", "Check gallery mouse reporting and terminal cleanup").dependOn(&gallery_terminal_test.step);
    const reload_consumer_test = b.addSystemCommand(&.{ "python3", "scripts/test-consumer.py", "--reload" });
    reload_consumer_test.setCwd(b.path("."));
    b.step("test-reload-consumer", "Build and test the public reload API outside the checkout").dependOn(&reload_consumer_test.step);
    const keyboard_units = b.addSystemCommand(&.{ "bun", "test", "tests/keyboard.test.ts" });
    keyboard_units.setCwd(b.path("."));
    const keyboard_pty = b.addSystemCommand(&.{ "python3", "scripts/test-keyboard.py" });
    keyboard_pty.setCwd(b.path("."));
    keyboard_pty.addArtifactArg(exe);
    const keyboard_step = b.step("test-keyboard", "Test keyboard parsing, held state, game physics and injected PTY negotiation");
    keyboard_step.dependOn(&keyboard_units.step);
    keyboard_step.dependOn(&keyboard_pty.step);
    const reload_terminal_test = b.addSystemCommand(&.{ "python3", "scripts/test-reload.py" });
    reload_terminal_test.setCwd(b.path("."));
    reload_terminal_test.addArtifactArg(exe);
    b.step("test-reload", "Check fresh runtime replacement and screen continuity in a disposable PTY").dependOn(&reload_terminal_test.step);
    const live_terminal_test = b.addSystemCommand(&.{ "python3", "scripts/test-live.py" });
    live_terminal_test.setCwd(b.path("."));
    live_terminal_test.addArtifactArg(exe);
    b.step("test-live", "Check disk loading and live file watching in a disposable PTY").dependOn(&live_terminal_test.step);
    const lab_terminal_test = b.addSystemCommand(&.{ "python3", "scripts/test-mouse.py" });
    lab_terminal_test.setCwd(b.path("."));
    lab_terminal_test.addArtifactArg(exe);
    lab_terminal_test.addArg("--lab");
    b.step("test-lab", "Check graphics lab terminal cleanup").dependOn(&lab_terminal_test.step);
    const messages_terminal_test = b.addSystemCommand(&.{ "python3", "scripts/test-mouse.py" });
    messages_terminal_test.setCwd(b.path("."));
    messages_terminal_test.addArtifactArg(exe);
    messages_terminal_test.addArg("--messages");
    b.step("test-messages", "Check worker wakeups and terminal cleanup with queued work").dependOn(&messages_terminal_test.step);
    const tmux_test = b.addSystemCommand(&.{ "python3", "scripts/test-tmux.py" });
    tmux_test.setCwd(b.path("."));
    tmux_test.addArtifactArg(exe);
    b.step("test-tmux", "Check probe title safety in a disposable tmux server, requires tmux and Python 3").dependOn(&tmux_test.step);

    const bundle = b.addSystemCommand(&.{ "bun", "scripts/bundle.ts" });
    bundle.setCwd(b.path("."));
    b.step("bundle", "Regenerate the checked-in JavaScript bundle using Bun").dependOn(&bundle.step);
    const bindings = b.addSystemCommand(&.{ "bun", "scripts/generate-bindings.ts" });
    bindings.setCwd(b.path("."));
    bundle.step.dependOn(&bindings.step);
    const paint_bundle = b.addSystemCommand(&.{ "bun", "scripts/bundle.ts", "--termpaint" });
    paint_bundle.setCwd(b.path("."));
    paint_bundle.step.dependOn(&bindings.step);
    b.step("bundle-termpaint", "Regenerate the standalone paint JS bundle").dependOn(&paint_bundle.step);
    bundle.step.dependOn(&paint_bundle.step);
}
