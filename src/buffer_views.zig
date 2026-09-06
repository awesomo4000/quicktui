//! UI-thread-only registry for bounded terminal-buffer reads. Addresses never
//! leave native code; QuickJS objects retain these generational pool handles.
const std = @import("std");
const poolside = @import("poolside");
const View = struct { buffer: u32, bytes: ?[*]const u8, length: usize };
const Views = poolside.TaggedPool(View, struct {});
var views = Views.init(std.heap.c_allocator);

export fn qt_view_create(buffer: u32, bytes: ?[*]const u8, length: usize) u64 {
    if (bytes == null) return 0;
    const handle = views.create(.{ .buffer = buffer, .bytes = bytes, .length = length }) catch return 0;
    return @bitCast(handle);
}
export fn qt_view_resolve(token: u64, offset: usize, length: usize) ?[*]const u8 {
    const view = views.get(@bitCast(token)) orelse return null;
    const bytes = view.bytes orelse return null;
    if (offset > view.length or length > view.length - offset) return null;
    return bytes + offset;
}
export fn qt_view_release(token: u64) void {
    _ = views.discard(@bitCast(token));
}
export fn qt_views_invalidate(buffer: u32) void {
    var it = views.iterator();
    while (it.next()) |entry| {
        if (entry.value.buffer == buffer) entry.value.bytes = null;
    }
}
export fn qt_views_clear() void {
    views.clearRetainingCapacity();
}
export fn qt_views_deinit() void {
    views.deinit();
    views = Views.init(std.heap.c_allocator);
}

test "buffer view bounds, revocation, and stale generations" {
    defer qt_views_deinit();
    const bytes = [_]u8{ 1, 2, 3, 4 };
    const first = qt_view_create(7, &bytes, bytes.len);
    try std.testing.expect(first != 0);
    try std.testing.expectEqual(@as(u8, 3), qt_view_resolve(first, 2, 2).?[0]);
    try std.testing.expect(qt_view_resolve(first, 3, 2) == null);
    try std.testing.expect(qt_view_resolve(first, std.math.maxInt(usize), 1) == null);
    try std.testing.expect(qt_view_resolve(first, 0, std.math.maxInt(usize)) == null);
    qt_view_release(first);
    const next = qt_view_create(7, &bytes, bytes.len);
    try std.testing.expect(next != first);
    try std.testing.expect(qt_view_resolve(first, 0, 1) == null);
    qt_views_invalidate(7);
    try std.testing.expect(qt_view_resolve(next, 0, 1) == null);
    const last = qt_view_create(8, &bytes, bytes.len);
    qt_views_clear();
    try std.testing.expect(qt_view_resolve(last, 0, 1) == null);
}
