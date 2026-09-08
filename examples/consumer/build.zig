const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dep = b.dependency("quicktui", .{ .target = target, .optimize = optimize });
    const exe = b.addExecutable(.{ .name = "consumer", .root_module = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "quicktui", .module = dep.module("quicktui") }},
    }) });
    b.installArtifact(exe);
}
