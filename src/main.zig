const runtime = @import("quicktui");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 2 and std.mem.eql(u8, args[1], "--smoke")) {
        return runtime.evaluate(@embedFile("app.js"));
    }
    if (args.len == 2 and std.mem.eql(u8, args[1], "--mouse")) {
        return runtime.runCounter(@embedFile("mouse.js"), false);
    }
    if (args.len == 2 and std.mem.eql(u8, args[1], "--mouse-self-test")) {
        return runtime.runCounter(@embedFile("mouse.js"), true);
    }
    const headless = args.len == 2 and std.mem.eql(u8, args[1], "--self-test");
    if (args.len > 1 and !headless) {
        std.debug.print("Usage: quicktui [--mouse | --self-test | --smoke]\n", .{});
        return error.InvalidArguments;
    }
    try runtime.runCounter(@embedFile("counter.js"), headless);
}
