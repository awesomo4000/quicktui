const runtime = @import("quicktui");
const std = @import("std");
const examples = @embedFile("examples.js");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
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
    const headless = args.len == 2 and std.mem.eql(u8, args[1], "--self-test");
    if (args.len > 1 and !headless) {
        std.debug.print("Usage: quicktui [--lab | --messages | --gallery | --mouse | --self-test | --smoke]\n", .{});
        return error.InvalidArguments;
    }
    try runtime.runCounter(examples, headless);
}
