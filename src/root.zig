comptime {
    _ = @import("buffer_views.zig");
}
const std = @import("std");

extern "c" fn quicktui_eval(source: [*:0]const u8, len: usize, diagnostics: c_int) c_int;
/// Optional application-owned transport. Callbacks run on the UI thread and must
/// not block. send copies bytes before returning; receive copies into the host
/// buffer. Return -1 for empty receive, 0 for rejected send, 1 for accepted send.
/// wake_fd must stay readable while replies remain queued. receive consumes its
/// wake notification along with the message. The host never reads or closes it.
/// Messages are UTF-8 strings, at most 4096 bytes. The endpoint outlives runWithMessages.
pub const MessageEndpoint = extern struct {
    context: ?*anyopaque,
    wake_fd: c_int,
    send: *const fn (?*anyopaque, [*]const u8, usize) callconv(.c) c_int,
    receive: *const fn (?*anyopaque, [*]u8, usize) callconv(.c) isize,
    /// Optional binary payload lookup. Successful borrows must remain stable until
    /// release_buffer. Host copies into a JS ArrayBuffer before releasing, max 4 MiB.
    borrow_buffer: ?*const fn (?*anyopaque, u32, *usize) callconv(.c) ?[*]const u8 = null,
    release_buffer: ?*const fn (?*anyopaque) callconv(.c) void = null,
};
extern "c" fn quicktui_app_messages(source: [*:0]const u8, len: usize, headless: c_int, example: [*:0]const u8, endpoint: *const MessageEndpoint) c_int;
pub fn runWithMessages(source: [:0]const u8, example: [:0]const u8, headless: bool, endpoint: *const MessageEndpoint) error{CounterFailed}!void {
    if (quicktui_app_messages(source.ptr, source.len, @intFromBool(headless), example.ptr, endpoint) != 0) return error.CounterFailed;
}

extern "c" fn quicktui_app(source: [*:0]const u8, len: usize, headless: c_int, example: [*:0]const u8) c_int;

pub fn runCounter(source: [:0]const u8, headless: bool) error{CounterFailed}!void {
    return runExample(source, "counter", headless);
}

pub fn runExample(source: [:0]const u8, example: [:0]const u8, headless: bool) error{CounterFailed}!void {
    if (quicktui_app(source.ptr, source.len, @intFromBool(headless), example.ptr) != 0) return error.CounterFailed;
}
extern "c" fn createOptimizedBuffer(width: u32, height: u32, respect_alpha: u8, width_method: u8, id: ?[*]const u8, id_len: u32) u32;
extern "c" fn destroyOptimizedBuffer(handle: u32) void;
extern "c" fn getBufferWidth(handle: u32) u32;
extern "c" fn getBufferHeight(handle: u32) u32;

/// Evaluate a bundled script, then drain its pending promise jobs.
/// Each invocation owns and releases a fresh QuickJS runtime.
pub fn evaluate(source: [:0]const u8) error{JavaScriptFailed}!void {
    try evaluateWithDiagnostics(source, true);
}

fn evaluateWithDiagnostics(source: [:0]const u8, diagnostics: bool) error{JavaScriptFailed}!void {
    if (quicktui_eval(source.ptr, source.len, @intFromBool(diagnostics)) != 0) return error.JavaScriptFailed;
}

// The bridge calls into Zig, which uses the real OpenTUI handle ABI.
export fn quicktui_native_probe() c_int {
    const handle = createOptimizedBuffer(32, 8, 0, 0, "quicktui", 8);
    if (handle == 0) return -1;
    defer destroyOptimizedBuffer(handle);
    if (getBufferWidth(handle) != 32 or getBufferHeight(handle) != 8) return -1;
    return 32;
}

test "JavaScript evaluates and reaches the native OpenTUI ABI" {
    try evaluate("if (nativeProbe() !== 32) throw new Error('native probe failed');");
}

test "pending jobs run and report exceptions" {
    try evaluate("Promise.resolve().then(() => { if (nativeProbe() !== 32) throw new Error('probe'); });");
    try std.testing.expectError(error.JavaScriptFailed, evaluateWithDiagnostics("Promise.resolve().then(() => { throw new Error('expected job failure'); });", false));
}

test "syntax and runtime exceptions fail evaluation" {
    try std.testing.expectError(error.JavaScriptFailed, evaluateWithDiagnostics("const = ;", false));
    try std.testing.expectError(error.JavaScriptFailed, evaluateWithDiagnostics("throw new Error('expected failure');", false));
}

test "native handles survive repeated allocation and destruction" {
    try evaluate("for (let i = 0; i < 100; i++) if (nativeProbe() !== 32) throw new Error('probe');");
}

test "endless promise jobs stop at the host job limit" {
    try std.testing.expectError(error.JavaScriptFailed, evaluateWithDiagnostics("function next() { Promise.resolve().then(next); } next();", false));
}

test "statically linked Yoga computes layout" {
    const yoga = struct {
        extern "c" fn YGNodeNew() ?*anyopaque;
        extern "c" fn YGNodeFree(node: *anyopaque) void;
        extern "c" fn YGNodeStyleSetWidth(node: *anyopaque, width: f32) void;
        extern "c" fn YGNodeStyleSetHeight(node: *anyopaque, height: f32) void;
        extern "c" fn YGNodeCalculateLayout(node: *anyopaque, width: f32, height: f32, direction: c_int) void;
        extern "c" fn YGNodeLayoutGetWidth(node: *anyopaque) f32;
        extern "c" fn YGNodeLayoutGetHeight(node: *anyopaque) f32;
    };
    const node = yoga.YGNodeNew() orelse return error.OutOfMemory;
    defer yoga.YGNodeFree(node);
    yoga.YGNodeStyleSetWidth(node, 32);
    yoga.YGNodeStyleSetHeight(node, 8);
    yoga.YGNodeCalculateLayout(node, 80, 24, 1);
    try std.testing.expectEqual(@as(f32, 32), yoga.YGNodeLayoutGetWidth(node));
    try std.testing.expectEqual(@as(f32, 8), yoga.YGNodeLayoutGetHeight(node));
}

test "opaque terminal buffer views reject fabrication and expired storage" {
    // Repeat to exercise runtime teardown and finalizers, too.
    for (0..2) |_| try runExample(@embedFile("buffer_views_test.js"), "buffer-views-test", true);
}
