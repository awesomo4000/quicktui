const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dep = b.dependency("quicktui", .{ .target = target, .optimize = optimize, .@"source-loader" = false });
    const exe = b.addExecutable(.{ .name = "consumer", .root_module = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "quicktui", .module = dep.module("quicktui") }},
    }) });
    const pack = @import("quicktui").addModulePack(b, dep, b.path("app.tsx"));
    exe.root_module.addAnonymousImport("app.pack", .{ .root_source_file = pack });
    b.installArtifact(exe);
}
