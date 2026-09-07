const std = @import("std");
const runtime = @import("quicktui");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const headless = args.len == 2 and std.mem.eql(u8, args[1], "--self-test");
    if (args.len > 2 or (args.len == 2 and std.mem.startsWith(u8, args[1], "-") and !headless)) {
        std.debug.print("Usage: termpaint [drawing.tpaint]\n", .{});
        return error.InvalidArguments;
    }
    var temporary: @import("examples/lab_presets.zig").Temporary = .{};
    if (headless) try temporary.init();
    defer if (headless) temporary.deinit();
    var worker: @import("examples/editor_worker.zig").Worker = .{ .enable_gif = true };
    worker.initial_path = if (headless) try std.fmt.allocPrint(init.arena.allocator(), "{s}/1.json", .{temporary.directory}) else if (args.len == 2) args[1] else "";
    if (worker.initial_path.len > 512) return error.PathTooLong;
    try worker.start();
    defer worker.stop();
    const endpoint = worker.endpoint();
    try runtime.runWithMessages(@embedFile("termpaint.js"), "termpaint", headless, &endpoint);
}
