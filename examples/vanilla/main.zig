const std = @import("std");
const quicktui = @import("quicktui");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    try quicktui.runApp(@embedFile("app.js"), .{ .headless = args.len > 1 and std.mem.eql(u8, args[1], "--self-test") });
}
