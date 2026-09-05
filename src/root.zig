const std = @import("std");

extern "c" fn quicktui_eval(source: [*:0]const u8, len: usize, diagnostics: c_int) c_int;
extern "c" fn quicktui_app(source: [*:0]const u8, len: usize, headless: c_int) c_int;

pub fn runCounter(source: [:0]const u8, headless: bool) error{CounterFailed}!void {
    if (quicktui_app(source.ptr, source.len, @intFromBool(headless)) != 0) return error.CounterFailed;
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
