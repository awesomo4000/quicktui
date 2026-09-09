const runtime = @import("quicktui");
const std = @import("std");
const examples = @embedFile("examples.js");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 2) {
        for ([_][:0]const u8{ "game", "keyboard" }) |name| {
            const flag = try std.fmt.allocPrint(init.arena.allocator(), "--{s}", .{name});
            const check = try std.fmt.allocPrint(init.arena.allocator(), "--{s}-self-test", .{name});
            if (std.mem.eql(u8, args[1], flag) or std.mem.eql(u8, args[1], check)) return runtime.runExample(examples, name, std.mem.eql(u8, args[1], check));
        }
    }
    if (args.len == 2 and (std.mem.eql(u8, args[1], "--reload") or std.mem.eql(u8, args[1], "--reload-self-test"))) {
        var worker: @import("examples/message_worker.zig").Worker = .{};
        try worker.start();
        defer worker.stop();
        const endpoint = worker.endpoint();
        return runtime.runReloadable(examples, "reload", std.mem.eql(u8, args[1], "--reload-self-test"), &endpoint);
    }
    if (args.len == 2 and std.mem.eql(u8, args[1], "--smoke")) {
        return runtime.evaluate(examples);
    }
    if (args.len == 2 and std.mem.eql(u8, args[1], "--mouse")) {
        return runtime.runExample(examples, "mouse", false);
    }
    if (args.len == 2 and std.mem.eql(u8, args[1], "--mouse-self-test")) {
        return runtime.runExample(examples, "mouse", true);
    }
    if (args.len == 2 and (std.mem.eql(u8, args[1], "--gallery") or std.mem.eql(u8, args[1], "--gallery-self-test"))) {
        return runtime.runExample(examples, "gallery", std.mem.eql(u8, args[1], "--gallery-self-test"));
    }
    if (args.len >= 2 and (std.mem.eql(u8, args[1], "--editor") or std.mem.eql(u8, args[1], "--editor-self-test"))) {
        if (args.len > 3) return error.InvalidArguments;
        const headless = std.mem.eql(u8, args[1], "--editor-self-test");
        var temporary: @import("examples/lab_presets.zig").Temporary = .{};
        if (headless) try temporary.init();
        defer if (headless) temporary.deinit();
        var worker: @import("examples/editor_worker.zig").Worker = .{};
        worker.initial_path = if (headless) try std.fmt.allocPrint(init.arena.allocator(), "{s}/1.json", .{temporary.directory}) else if (args.len == 3) args[2] else "";
        if (worker.initial_path.len > 512) return error.PathTooLong;
        try worker.start();
        defer worker.stop();
        const endpoint = worker.endpoint();
        return runtime.runWithMessages(examples, "editor", headless, &endpoint);
    }
    if (args.len == 2 and (std.mem.eql(u8, args[1], "--messages") or std.mem.eql(u8, args[1], "--messages-self-test"))) {
        var worker: @import("examples/message_worker.zig").Worker = .{};
        try worker.start();
        defer worker.stop();
        const endpoint = worker.endpoint();
        return runtime.runWithMessages(examples, "messages", std.mem.eql(u8, args[1], "--messages-self-test"), &endpoint);
    }
    if (args.len == 2 and (std.mem.eql(u8, args[1], "--lab") or std.mem.eql(u8, args[1], "--lab-self-test"))) {
        const headless = std.mem.eql(u8, args[1], "--lab-self-test");
        var temporary: @import("examples/lab_presets.zig").Temporary = .{};
        if (headless) try temporary.init();
        defer if (headless) temporary.deinit();
        var worker: @import("examples/lab_worker.zig").Worker = .{};
        if (headless) worker.preset_directory = temporary.directory;
        try worker.start();
        defer worker.stop();
        const endpoint = worker.endpoint();
        return runtime.runWithMessages(examples, "lab", std.mem.eql(u8, args[1], "--lab-self-test"), &endpoint);
    }
    if (args.len >= 2 and (std.mem.eql(u8, args[1], "--live") or std.mem.eql(u8, args[1], "--live-self-test"))) {
        if (args.len > 3) return error.InvalidArguments;
        var loader: @import("examples/live_loader.zig").Loader = .{};
        if (args.len == 3) loader.directory = args[2];
        try loader.start();
        defer loader.stop();
        const endpoint = loader.endpoint();
        return runtime.runWithMessages(examples, "live", std.mem.eql(u8, args[1], "--live-self-test"), &endpoint);
    }
    const headless = args.len == 2 and std.mem.eql(u8, args[1], "--self-test");
    if (args.len > 1 and !headless) {
        std.debug.print("Usage: quicktui [--game | --keyboard | --reload | --editor [file] | --live [directory] | --lab | --messages | --gallery | --mouse | --self-test | --smoke]\n", .{});
        return error.InvalidArguments;
    }
    try runtime.runCounter(examples, headless);
}
