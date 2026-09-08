//! Demo backend. No QuickJS values or renderer calls cross the thread boundary.
const std = @import("std");
const runtime = @import("quicktui");
const c = @cImport({
    @cInclude("pthread.h");
    @cInclude("unistd.h");
    @cInclude("fcntl.h");
    @cInclude("time.h");
});
const Message = struct {
    bytes: [4096]u8 = undefined,
    len: usize = 0,
};
fn Queue(comptime capacity: usize) type {
    return struct {
        items: [capacity]Message = undefined,
        head: usize = 0,
        len: usize = 0,
        fn push(self: *@This(), bytes: []const u8) bool {
            if (self.len == capacity or bytes.len > 4096) return false;
            const item = &self.items[(self.head + self.len) % capacity];
            @memcpy(item.bytes[0..bytes.len], bytes);
            item.len = bytes.len;
            self.len += 1;
            return true;
        }
        fn pop(self: *@This()) ?Message {
            if (self.len == 0) return null;
            const result = self.items[self.head];
            self.head = (self.head + 1) % capacity;
            self.len -= 1;
            return result;
        }
    };
}
pub const Worker = struct {
    mutex: c.pthread_mutex_t = undefined,
    changed: c.pthread_cond_t = undefined,
    incoming: Queue(256) = .{},
    outgoing: Queue(16) = .{},
    wake: [2]c_int = .{ -1, -1 },
    stopping: bool = false,
    grid_columns: u32 = 0,
    grid_rows: u32 = 0,
    thread: ?std.Thread = null,

    // The Worker address must stay stable until stop has joined its thread.
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
        return .{ .context = self, .wake_fd = self.wake[0], .send = send, .receive = receive };
    }
    fn send(context: ?*anyopaque, bytes: [*]const u8, len: usize) callconv(.c) c_int {
        const self: *Worker = @ptrCast(@alignCast(context.?));
        _ = c.pthread_mutex_lock(&self.mutex);
        defer _ = c.pthread_mutex_unlock(&self.mutex);
        if (self.stopping) return 0;
        const payload = bytes[0..len];
        if (std.mem.startsWith(u8, payload, "grid:")) {
            var parts = std.mem.splitScalar(u8, payload[5..], ':');
            const columns = std.fmt.parseInt(u32, parts.next() orelse return 0, 10) catch return 0;
            const rows = std.fmt.parseInt(u32, parts.next() orelse return 0, 10) catch return 0;
            if (parts.next() != null or columns == 0 or rows == 0 or @as(u64, columns) * rows > 65536) return 0;
            // Latest-value configuration mailbox: resizing must not wait behind jobs.
            self.grid_columns = columns;
            self.grid_rows = rows;
            _ = c.pthread_cond_signal(&self.changed);
            return 1;
        }
        if (!self.incoming.push(payload)) return 0;
        _ = c.pthread_cond_signal(&self.changed);
        return 1;
    }
    fn receive(context: ?*anyopaque, bytes: [*]u8, capacity: usize) callconv(.c) isize {
        const self: *Worker = @ptrCast(@alignCast(context.?));
        _ = c.pthread_mutex_lock(&self.mutex);
        defer _ = c.pthread_mutex_unlock(&self.mutex);
        const message = self.outgoing.pop() orelse return -1;
        std.debug.assert(message.len <= capacity);
        @memcpy(bytes[0..message.len], message.bytes[0..message.len]);
        var byte: u8 = 0;
        while (true) {
            const result = c.read(self.wake[0], &byte, 1);
            if (result == 1 or std.posix.errno(result) != .INTR) break;
        }
        _ = c.pthread_cond_signal(&self.changed);
        return @intCast(message.len);
    }
    fn emit(self: *Worker, bytes: []const u8) bool {
        _ = c.pthread_mutex_lock(&self.mutex);
        defer _ = c.pthread_mutex_unlock(&self.mutex);
        while (!self.stopping and self.outgoing.len == 16) _ = c.pthread_cond_wait(&self.changed, &self.mutex);
        if (self.stopping) return false;
        const pushed = self.outgoing.push(bytes);
        std.debug.assert(pushed);
        const byte: u8 = 1;
        // At most 16 outstanding bytes, one per queued event. Retry interrupted writes.
        while (true) {
            const result = c.write(self.wake[1], &byte, 1);
            if (result == 1) break;
            if (std.posix.errno(result) != .INTR) return false;
        }
        return true;
    }
    fn milliseconds() i64 {
        var time: c.timespec = undefined;
        _ = c.clock_gettime(c.CLOCK_MONOTONIC, &time);
        return time.tv_sec * 1000 + @divTrunc(time.tv_nsec, 1_000_000);
    }
    fn pulse(self: *Worker, rng: std.Random, next: *i64, sequence: *u32) bool {
        const now = milliseconds();
        if (now < next.*) return true;
        _ = c.pthread_mutex_lock(&self.mutex);
        const columns = self.grid_columns;
        const rows = self.grid_rows;
        _ = c.pthread_mutex_unlock(&self.mutex);
        if (columns == 0 or rows == 0) {
            next.* = now + 1000;
            return true;
        }
        sequence.* +%= 1;
        var selected: [10]u32 = undefined;
        const count = chooseCells(rng, columns * rows, &selected);
        var bytes: [512]u8 = undefined;
        var used = (std.fmt.bufPrint(&bytes, "{{\"type\":\"blink\",\"sequence\":{d},\"columns\":{d},\"rows\":{d},\"atMs\":{d},\"cells\":[", .{ sequence.*, columns, rows, now }) catch unreachable).len;
        for (selected[0..count], 0..) |cell, i| {
            used += (std.fmt.bufPrint(bytes[used..], "{s}{d}", .{ if (i == 0) "" else ",", cell }) catch unreachable).len;
        }
        @memcpy(bytes[used..][0..2], "]}");
        used += 2;
        if (!self.emit(bytes[0..used])) return false;
        next.* = milliseconds() + rng.intRangeAtMost(i64, 1000, 5000);
        return true;
    }
    fn run(self: *Worker) void {
        var pulse_prng = std.Random.DefaultPrng.init(@intCast(milliseconds()));
        const pulse_rng = pulse_prng.random();
        var next_pulse = milliseconds() + pulse_rng.intRangeAtMost(i64, 1000, 5000);
        var pulse_sequence: u32 = 0;
        while (true) {
            if (!self.pulse(pulse_rng, &next_pulse, &pulse_sequence)) return;
            _ = c.pthread_mutex_lock(&self.mutex);
            if (!self.stopping and self.incoming.len == 0) {
                // Wake for either a command or the next unsolicited native event.
                // pthread timed waits use realtime; event scheduling uses monotonic time.
                var deadline: c.timespec = undefined;
                _ = c.clock_gettime(c.CLOCK_REALTIME, &deadline);
                const wait_ms = @max(1, next_pulse - milliseconds());
                deadline.tv_nsec += @intCast(wait_ms * 1_000_000);
                deadline.tv_sec += @divTrunc(deadline.tv_nsec, 1_000_000_000);
                deadline.tv_nsec = @mod(deadline.tv_nsec, 1_000_000_000);
                _ = c.pthread_cond_timedwait(&self.changed, &self.mutex, &deadline);
                _ = c.pthread_mutex_unlock(&self.mutex);
                continue;
            }
            if (self.stopping) {
                _ = c.pthread_mutex_unlock(&self.mutex);
                return;
            }
            const message = self.incoming.pop().?;
            _ = c.pthread_mutex_unlock(&self.mutex);
            const payload = message.bytes[0..message.len];
            const spread = std.mem.startsWith(u8, payload, "spread:");
            const random = std.mem.startsWith(u8, payload, "random:");
            const id = std.fmt.parseInt(u32, if (spread or random) payload[7..] else payload, 10) catch continue;
            const count: u32 = if (spread or random) 10 else 1;
            if (id > std.math.maxInt(u32) - count) continue;
            var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(milliseconds())) ^ id);
            const rng = prng.random();
            const chains: usize = if (random) rng.intRangeAtMost(usize, 2, 3) else 0;
            var durations = [_]i64{500} ** 10;
            var starts = [_]i64{-1} ** 10;
            var progress = [_]i64{-1} ** 10;
            for (0..count) |i| {
                if (random) durations[i] = rng.intRangeAtMost(i64, 1000, 2200);
            }
            // Concurrent waits plus 2-3 serial pairs. Each random job runs for
            // 1-2.2 seconds, leaving scheduling margin below five seconds/batch.
            var remaining: usize = count;
            while (remaining > 0) {
                if (!self.pulse(pulse_rng, &next_pulse, &pulse_sequence)) return;
                const at_ms = milliseconds();
                for (0..count) |i| {
                    if (progress[i] == 100) continue;
                    if (starts[i] < 0) {
                        if (i < chains * 2 and i % 2 == 1 and progress[i - 1] != 100) continue;
                        starts[i] = at_ms;
                    }
                    const percent = @min(100, @divTrunc((at_ms - starts[i]) * 100, durations[i]));
                    const value = if (random) percent else @divTrunc(percent, 20) * 20;
                    if (value == progress[i]) continue;
                    progress[i] = value;
                    var buffer: [192]u8 = undefined;
                    const event = std.fmt.bufPrint(&buffer, "{{\"id\":{d},\"progress\":{d},\"type\":\"{s}\",\"atMs\":{d}}}", .{ id + i, value, if (value == 100) "done" else "progress", at_ms }) catch unreachable;
                    if (!self.emit(event)) return;
                    if (value == 100) remaining -= 1;
                }
                if (remaining > 0) {
                    const delay: c.timespec = .{ .tv_sec = 0, .tv_nsec = 50_000_000 };
                    _ = c.nanosleep(&delay, null);
                }
            }
        }
    }
};

test "bounded queue copies messages and preserves FIFO across wraparound" {
    var queue: Queue(2) = .{};
    var source = [_]u8{'a'};
    try std.testing.expect(queue.push(&source));
    source[0] = 'z';
    try std.testing.expect(queue.push("b"));
    try std.testing.expect(!queue.push("overflow"));
    try std.testing.expectEqual(@as(u8, 'a'), queue.pop().?.bytes[0]);
    try std.testing.expect(queue.push("c"));
    try std.testing.expectEqual(@as(u8, 'b'), queue.pop().?.bytes[0]);
    try std.testing.expectEqual(@as(u8, 'c'), queue.pop().?.bytes[0]);
    try std.testing.expect(queue.pop() == null);
}

// Floyd sampling chooses a unique subset without allocating a grid-sized pool.
fn chooseCells(rng: std.Random, total: u32, selected: *[10]u32) usize {
    if (total == 0) return 0;
    const count = rng.intRangeAtMost(u32, 1, @min(10, total));
    for (0..count) |i| {
        const j = total - count + @as(u32, @intCast(i));
        const candidate = rng.intRangeAtMost(u32, 0, j);
        selected[i] = if (std.mem.indexOfScalar(u32, selected[0..i], candidate) != null) j else candidate;
    }
    return count;
}

test "native blink selection is bounded and unique for small and large grids" {
    var prng = std.Random.DefaultPrng.init(42);
    for ([_]u32{ 1, 3, 10, 11, 250, 65536 }) |total| {
        for (0..100) |_| {
            var cells: [10]u32 = undefined;
            const count = chooseCells(prng.random(), total, &cells);
            try std.testing.expect(count >= 1 and count <= @min(10, total));
            for (cells[0..count], 0..) |cell, i| {
                try std.testing.expect(cell < total);
                try std.testing.expect(std.mem.indexOfScalar(u32, cells[0..i], cell) == null);
            }
        }
    }
}

test "shutdown wakes a worker blocked by a full reply queue" {
    for (0..8) |_| {
        var worker: Worker = .{};
        try worker.start();
        const endpoint_value = worker.endpoint();
        try std.testing.expectEqual(@as(c_int, 1), endpoint_value.send(endpoint_value.context, "spread:1", 8));
        const deadline = Worker.milliseconds() + 2000;
        var full = false;
        while (Worker.milliseconds() < deadline) {
            _ = c.pthread_mutex_lock(&worker.mutex);
            full = worker.outgoing.len == 16;
            _ = c.pthread_mutex_unlock(&worker.mutex);
            if (full) break;
            var delay: c.timespec = .{ .tv_sec = 0, .tv_nsec = 1_000_000 };
            _ = c.nanosleep(&delay, null);
        }
        worker.stop();
        try std.testing.expect(full);
    }
}
