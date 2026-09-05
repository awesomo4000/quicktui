const std = @import("std");
const runtime = @import("quicktui");
const glyphs = @import("lab_glyphs.zig");
const cpu = @import("lab_raster.zig");
const c = @cImport({
    @cInclude("pthread.h");
    @cInclude("unistd.h");
    @cInclude("fcntl.h");
    @cInclude("time.h");
});
pub const Worker = struct {
    mutex: c.pthread_mutex_t = undefined,
    changed: c.pthread_cond_t = undefined,
    wake: [2]c_int = .{ -1, -1 },
    thread: ?std.Thread = null,
    stopping: bool = false,
    scene: cpu.Scene = .{},
    dirty: bool = true,
    ready: [cpu.byte_count + glyphs.max_bytes]u8 = undefined,
    ready_len: usize = cpu.byte_count,
    ready_cols: u32 = 0,
    ready_rows: u32 = 0,
    ready_charset: u32 = 0,
    ready_tone: u32 = 0,
    frame_id: u32 = 0,
    taken_id: u32 = 0,
    pending: bool = false,
    dropped: u32 = 0,
    render_ms: f64 = 0,
    pub fn start(self: *Worker) !void {
        if (c.pthread_mutex_init(&self.mutex, null) != 0) return error.MutexInit;
        errdefer _ = c.pthread_mutex_destroy(&self.mutex);
        if (c.pthread_cond_init(&self.changed, null) != 0) return error.ConditionInit;
        errdefer _ = c.pthread_cond_destroy(&self.changed);
        if (c.pipe(&self.wake) != 0) return error.Pipe;
        errdefer for (self.wake) |fd| {
            _ = c.close(fd);
        };
        for (self.wake) |fd| {
            if (c.fcntl(fd, c.F_SETFL, @as(c_int, c.O_NONBLOCK)) < 0 or c.fcntl(fd, c.F_SETFD, @as(c_int, c.FD_CLOEXEC)) < 0) return error.PipeFlags;
        }
        self.thread = try std.Thread.spawn(.{}, run, .{self});
    }
    pub fn stop(self: *Worker) void {
        _ = c.pthread_mutex_lock(&self.mutex);
        self.stopping = true;
        _ = c.pthread_cond_broadcast(&self.changed);
        _ = c.pthread_mutex_unlock(&self.mutex);
        if (self.thread) |thread| thread.join();
        for (self.wake) |fd| {
            _ = c.close(fd);
        }
        _ = c.pthread_cond_destroy(&self.changed);
        _ = c.pthread_mutex_destroy(&self.mutex);
    }
    pub fn endpoint(self: *Worker) runtime.MessageEndpoint {
        return .{ .context = self, .wake_fd = self.wake[0], .send = send, .receive = receive, .borrow_buffer = borrow, .release_buffer = release };
    }
    fn cast(context: ?*anyopaque) *Worker {
        return @ptrCast(@alignCast(context.?));
    }
    fn send(context: ?*anyopaque, bytes: [*]const u8, len: usize) callconv(.c) c_int {
        const parsed = std.json.parseFromSlice(cpu.Scene, std.heap.c_allocator, bytes[0..len], .{}) catch return 0;
        defer parsed.deinit();
        const scene = parsed.value;
        if (scene.charset > 8 or scene.cols < 1 or scene.cols > glyphs.max_cols or scene.rows < 1 or scene.rows > glyphs.max_rows or scene.fps < 1 or scene.fps > 120 or scene.shape > 4 or scene.palette > 2 or !std.math.isFinite(scene.angle) or !std.math.isFinite(scene.tilt) or !std.math.isFinite(scene.zoom) or scene.zoom < 0.3 or scene.zoom > 1.4) return 0;
        if (scene.tone > 3 or !std.math.isFinite(scene.brightness) or @abs(scene.brightness) > 1 or
            !std.math.isFinite(scene.contrast) or scene.contrast < 0.25 or scene.contrast > 4 or
            !std.math.isFinite(scene.dot_scale) or scene.dot_scale < 0 or scene.dot_scale > 5 or
            !std.math.isFinite(scene.fractal_zoom) or scene.fractal_zoom < 0.5 or scene.fractal_zoom > 1e10 or
            !std.math.isFinite(scene.center_x) or @abs(scene.center_x) > 4 or
            !std.math.isFinite(scene.center_y) or @abs(scene.center_y) > 4) return 0;
        const self = cast(context);
        _ = c.pthread_mutex_lock(&self.mutex);
        defer _ = c.pthread_mutex_unlock(&self.mutex);
        if (self.stopping) return 0;
        self.scene = scene;
        self.dirty = true;
        _ = c.pthread_cond_signal(&self.changed);
        return 1;
    }
    fn receive(context: ?*anyopaque, bytes: [*]u8, capacity: usize) callconv(.c) isize {
        const self = cast(context);
        _ = c.pthread_mutex_lock(&self.mutex);
        defer _ = c.pthread_mutex_unlock(&self.mutex);
        if (!self.pending) return -1;
        const message = std.fmt.bufPrint(bytes[0..capacity], "{{\"type\":\"frame-ready\",\"id\":{d},\"width\":{d},\"height\":{d},\"ms\":{d:.2},\"dropped\":{d},\"cols\":{d},\"rows\":{d},\"charset\":{d},\"tone\":{d},\"glyph_bytes\":{d}}}", .{ self.frame_id, cpu.width, cpu.height, self.render_ms, self.dropped, self.ready_cols, self.ready_rows, self.ready_charset, self.ready_tone, self.ready_len - cpu.byte_count - (if (self.ready_charset > 0) self.ready_cols * self.ready_rows * 6 else @as(u32, 0)) }) catch return -1;
        self.pending = false;
        var byte: u8 = 0;
        while (true) {
            const result = c.read(self.wake[0], &byte, 1);
            if (result == 1 or std.posix.errno(result) != .INTR) break;
        }
        return @intCast(message.len);
    }
    // Keep the published pixels locked only while the UI host copies them.
    // Rendering happens into a separate worker-owned buffer, outside this lock.
    fn borrow(context: ?*anyopaque, id: u32, len: *usize) callconv(.c) ?[*]const u8 {
        const self = cast(context);
        _ = c.pthread_mutex_lock(&self.mutex);
        if (id != self.frame_id or id == self.taken_id) {
            _ = c.pthread_mutex_unlock(&self.mutex);
            return null;
        }
        self.taken_id = id;
        len.* = self.ready_len;
        return &self.ready;
    }
    fn release(context: ?*anyopaque) callconv(.c) void {
        _ = c.pthread_mutex_unlock(&cast(context).mutex);
    }
    fn now() f64 {
        var time: c.timespec = undefined;
        _ = c.clock_gettime(c.CLOCK_MONOTONIC, &time);
        return @as(f64, @floatFromInt(time.tv_sec)) * 1000 + @as(f64, @floatFromInt(time.tv_nsec)) / 1e6;
    }
    fn run(self: *Worker) void {
        var raster: cpu.Raster = undefined;
        var converter: glyphs.Converter = .{};
        var text: [glyphs.max_bytes]u8 = undefined;
        var phase: f32 = 0;
        var last_frame: f64 = 0;
        var was_playing = false;
        while (true) {
            _ = c.pthread_mutex_lock(&self.mutex);
            while (!self.stopping) {
                if (!self.dirty and !self.scene.playing) {
                    _ = c.pthread_cond_wait(&self.changed, &self.mutex);
                    continue;
                }
                const remaining = last_frame + 1000.0 / @as(f64, @floatFromInt(self.scene.fps)) - now();
                if (remaining <= 0) break;
                // Signals update the mailbox but cannot bypass the frame deadline.
                var deadline: c.timespec = undefined;
                _ = c.clock_gettime(c.CLOCK_REALTIME, &deadline);
                deadline.tv_nsec += @as(c_long, @intFromFloat(@ceil(remaining * 1e6)));
                deadline.tv_sec += @divTrunc(deadline.tv_nsec, 1_000_000_000);
                deadline.tv_nsec = @mod(deadline.tv_nsec, 1_000_000_000);
                _ = c.pthread_cond_timedwait(&self.changed, &self.mutex, &deadline);
            }
            if (self.stopping) {
                _ = c.pthread_mutex_unlock(&self.mutex);
                return;
            }
            var scene = self.scene;
            self.dirty = false;
            _ = c.pthread_mutex_unlock(&self.mutex);
            const began = now();
            if (scene.playing and was_playing) phase = @mod(phase + @as(f32, @floatCast((began - last_frame) * 0.00055)), std.math.pi * 200);
            last_frame = began;
            was_playing = scene.playing;
            scene.angle += phase;
            raster.render(scene);
            const text_len = if (scene.charset > 0) converter.render(&raster.pixels, scene.cols, scene.rows, scene.charset, scene.tone, &text) else 0;
            const elapsed = now() - began;
            _ = c.pthread_mutex_lock(&self.mutex);
            if (self.stopping) {
                _ = c.pthread_mutex_unlock(&self.mutex);
                return;
            }
            @memcpy(self.ready[0..cpu.byte_count], &raster.pixels);
            @memcpy(self.ready[cpu.byte_count..][0..text_len], text[0..text_len]);
            self.ready_len = cpu.byte_count + text_len;
            self.ready_cols = scene.cols;
            self.ready_rows = scene.rows;
            self.ready_charset = scene.charset;
            self.ready_tone = scene.tone;
            self.frame_id +%= 1;
            if (self.frame_id == 0) self.frame_id = 1;
            self.render_ms = elapsed;
            if (self.pending) self.dropped +%= 1 else {
                self.pending = true;
                const byte: u8 = 1;
                while (true) {
                    const result = c.write(self.wake[1], &byte, 1);
                    if (result == 1 or std.posix.errno(result) != .INTR) break;
                }
            }
            _ = c.pthread_mutex_unlock(&self.mutex);
        }
    }
};
test {
    _ = @import("lab_raster.zig");
}

test "binary frame lookup rejects stale and already consumed IDs" {
    var worker: Worker = .{};
    try std.testing.expectEqual(@as(c_int, 0), c.pthread_mutex_init(&worker.mutex, null));
    defer _ = c.pthread_mutex_destroy(&worker.mutex);
    worker.frame_id = 7;
    @memset(&worker.ready, 123);
    var len: usize = 0;
    try std.testing.expect(Worker.borrow(&worker, 6, &len) == null);
    const pixels = Worker.borrow(&worker, 7, &len).?;
    const valid = len == cpu.byte_count and pixels[0] == 123;
    Worker.release(&worker);
    try std.testing.expect(valid);
    try std.testing.expect(Worker.borrow(&worker, 7, &len) == null);
}

test "input floods cannot bypass the native frame limit" {
    var worker: Worker = .{};
    try worker.start();
    defer worker.stop();
    const began = Worker.now();
    const request = "{\"fps\":10}";
    while (Worker.now() - began < 350) {
        try std.testing.expectEqual(@as(c_int, 1), Worker.send(&worker, request.ptr, request.len));
        var pause = c.timespec{ .tv_sec = 0, .tv_nsec = 1_000_000 };
        _ = c.nanosleep(&pause, null);
    }
    _ = c.pthread_mutex_lock(&worker.mutex);
    const count = worker.frame_id;
    _ = c.pthread_mutex_unlock(&worker.mutex);
    try std.testing.expect(count >= 1 and count <= 4);
}
