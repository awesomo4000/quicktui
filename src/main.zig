const runtime = @import("quicktui");
const std = @import("std");
const examples = @embedFile("examples.js");
/// `zig build -Dmodule-image=true` embeds js/examples.ts precompiled.
const embedded_image: ?[]const u8 = if (@import("quicktui_app_options").module_image) @embedFile("quicktui-demo-image") else null;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const arena = init.arena.allocator();
    const source_root: ?[:0]const u8 = if (std.c.getenv("QUICKTUI_SOURCE")) |root| std.mem.span(root) else null;
    // `quicktui --build-image out.qtimg app.tsx [--demo]`: compile everything
    // app.tsx reaches into a module image. `--demo` bakes the demo assets in.
    if (args.len >= 4 and std.mem.eql(u8, args[1], "--build-image")) {
        if (args.len > 5 or (args.len == 5 and !std.mem.eql(u8, args[4], "--demo"))) return error.InvalidArguments;
        return runtime.modules.buildImage(arena, .{
            .root = source_root orelse runtime.modules.default_root,
            .entry = try runtime.modules.absolute(arena, args[3]),
            .demo_assets = args.len == 5,
        }, args[2]);
    }
    // `quicktui --run app.tsx` runs an application from source; `--run-image
    // app.qtimg` runs a prebuilt image with no checkout. Both take
    // [--reload] [--self-test]. Under --reload with --run, Ctrl+R re-reads
    // changed sources; unchanged modules come from the bytecode cache.
    if (args.len >= 3 and (std.mem.eql(u8, args[1], "--run") or std.mem.eql(u8, args[1], "--run-image"))) {
        var headless = false;
        var reload = false;
        for (args[3..]) |flag| {
            if (std.mem.eql(u8, flag, "--self-test")) headless = true else if (std.mem.eql(u8, flag, "--reload")) reload = true else return error.InvalidArguments;
        }
        if (std.mem.eql(u8, args[1], "--run-image")) {
            runtime.modules.enableImage(try runtime.modules.readImage(args[2]));
        } else try runtime.modules.enable(arena, .{
            .root = source_root orelse runtime.modules.default_root,
            .entry = try runtime.modules.absolute(arena, args[2]),
        });
        return runtime.runApp("", .{ .headless = headless, .reload = reload });
    }
    // QUICKTUI_IMAGE=<image> and/or QUICKTUI_SOURCE=<checkout> run the demos
    // from modules instead of the bundle (the image first, then the checkout).
    // Otherwise an embedded image, if built with one, replaces the bundle.
    if (std.c.getenv("QUICKTUI_IMAGE")) |path| runtime.modules.enableImage(try runtime.modules.readImage(std.mem.span(path))) else if (source_root == null) {
        if (embedded_image) |image| runtime.modules.enableImage(image);
    }
    if (source_root) |root| try runtime.modules.enable(arena, .{
        .root = root,
        .entry = "js/examples.ts",
        .demo_assets = true,
    });
    if (args.len == 2) {
        for ([_][:0]const u8{ "game", "keyboard", "vanilla" }) |name| {
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
        std.debug.print("Usage: quicktui [--run app.tsx [--reload] [--self-test] | --run-image app.qtimg [--reload] [--self-test] | --build-image out.qtimg app.tsx [--demo] | --vanilla | --game | --keyboard | --reload | --editor [file] | --live [directory] | --lab | --messages | --gallery | --mouse | --self-test | --smoke]\n", .{});
        return error.InvalidArguments;
    }
    try runtime.runCounter(examples, headless);
}
