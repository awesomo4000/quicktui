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
    runtime.addIncludePath(b.path("vendor/quickjs"));
    runtime.addCSourceFile(.{ .file = b.path("src/quickjs_bridge.c"), .flags = &.{"-std=c11"} });
    runtime.addCSourceFiles(.{ .files = &.{ "src/native_bridge.c", "src/native_generated.c", "src/app_host.c" }, .flags = &.{"-std=c11"} });
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
    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run the interactive React / QuickJS / OpenTUI counter").dependOn(&run.step);

    const tests = b.addTest(.{ .root_module = runtime });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Test JavaScript evaluation, jobs, errors, and native ABI calls");
    test_step.dependOn(&run_tests.step);
    const self_test = b.addRunArtifact(exe);
    self_test.addArg("--self-test");
    test_step.dependOn(&self_test.step);

    const mouse_test = b.addRunArtifact(exe);
    mouse_test.addArg("--mouse-self-test");
    test_step.dependOn(&mouse_test.step);

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
    const tmux_test = b.addSystemCommand(&.{ "python3", "scripts/test-tmux.py" });
    tmux_test.setCwd(b.path("."));
    tmux_test.addArtifactArg(exe);
    b.step("test-tmux", "Check probe title safety in a disposable tmux server, requires tmux and Python 3").dependOn(&tmux_test.step);

    const bundle = b.addSystemCommand(&.{ "bun", "scripts/bundle.ts" });
    bundle.setCwd(b.path("."));
    b.step("bundle", "Regenerate the checked-in JavaScript bundle using Bun").dependOn(&bundle.step);
    const bindings = b.addSystemCommand(&.{ "bun", "scripts/generate-bindings.ts" });
    bindings.setCwd(b.path("."));
    const counter_bundle = b.addSystemCommand(&.{ "bun", "scripts/counter-bundle.ts" });
    counter_bundle.setCwd(b.path("."));
    counter_bundle.step.dependOn(&bindings.step);
    bundle.step.dependOn(&counter_bundle.step);
}
