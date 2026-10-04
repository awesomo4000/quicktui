//! quicktui-pack: build a module pack at build time, for @embedFile.
//!
//!   quicktui-pack <checkout> <entry> <out.pack> [--demo] [--app-root <path>] [--depfile <path>]
//!
//! Library modules resolve inside <checkout> (js/, vendor/). Nothing is
//! evaluated as an ES module; CommonJS export discovery can execute dependencies.
//! No disk cache is used, so the output depends only on the
//! files listed in the depfile and on this tool's embedded loader.
const std = @import("std");
const modules = @import("modules.zig");

comptime {
    for (@typeInfo(modules).@"struct".decls) |decl| _ = &@field(modules, decl.name);
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 4) return usage();
    var demo = false;
    var app_root: ?[:0]const u8 = null;
    var depfile: [:0]const u8 = "";
    var i: usize = 4;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--demo")) demo = true else if (std.mem.eql(u8, args[i], "--depfile") and i + 1 < args.len) {
            i += 1;
            depfile = args[i];
        } else if (std.mem.eql(u8, args[i], "--app-root") and i + 1 < args.len) {
            i += 1;
            app_root = args[i];
        } else return usage();
    }
    try modules.buildPack(arena, .{
        .root = args[1],
        .entry = try modules.absolute(arena, args[2]),
        .demo_assets = demo,
        .app_root = app_root,
        .cache_dir = "",
        .depfile = depfile,
        // zig build fails a run step that writes to stderr; errors still print.
        .quiet = depfile.len > 0,
    }, args[3]);
}

fn usage() error{InvalidArguments} {
    std.debug.print("usage: quicktui-pack <checkout> <entry> <out.pack> [--demo] [--app-root <path>] [--depfile <path>]\n", .{});
    return error.InvalidArguments;
}
