const std = @import("std");
const runtime = @import("quicktui");
const c = @cImport({
    @cInclude("pthread.h");
    @cInclude("unistd.h");
    @cInclude("fcntl.h");
    @cInclude("stdio.h");
    @cInclude("time.h");
});
pub const limit = 1024 * 1024;
const Request = struct { load: enum { counter, clock, clear }, watch: bool = false, epoch: u32 = 0 };
pub const Loader = struct {
    directory: []const u8 = "examples/live",
    mutex: c.pthread_mutex_t = undefined,
    changed: c.pthread_cond_t = undefined,
    wake: [2]c_int = .{ -1, -1 },
    thread: ?std.Thread = null,
    stopping: bool = false,
    request: Request = .{ .load = .counter },
    requested: bool = false,
    watching: bool = false,
    published_file: Request = .{ .load = .counter },
    selected: Request = .{ .load = .counter },
    published: [limit]u8 = undefined,
    length: usize = 0,
    id: u32 = 0,
    taken: u32 = 0,
    pending: bool = false,
    failure: []const u8 = "",
    pub fn start(self: *Loader) !void {
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
    pub fn stop(self: *Loader) void {
        _ = c.pthread_mutex_lock(&self.mutex);
        self.stopping = true;
        _ = c.pthread_cond_signal(&self.changed);
        _ = c.pthread_mutex_unlock(&self.mutex);
        if (self.thread) |thread| thread.join();
        for (self.wake) |fd| {
            _ = c.close(fd);
        }
        _ = c.pthread_cond_destroy(&self.changed);
        _ = c.pthread_mutex_destroy(&self.mutex);
    }
    pub fn endpoint(self: *Loader) runtime.MessageEndpoint {
        return .{ .context = self, .wake_fd = self.wake[0], .send = send, .receive = receive, .borrow_buffer = borrow, .release_buffer = release };
    }
    fn cast(context: ?*anyopaque) *Loader {
        return @ptrCast(@alignCast(context.?));
    }
    fn send(context: ?*anyopaque, bytes: [*]const u8, length: usize) callconv(.c) c_int {
        if (length > 512) return 0;
        const parsed = std.json.parseFromSlice(Request, std.heap.c_allocator, bytes[0..length], .{}) catch return 0;
        defer parsed.deinit();
        const self = cast(context);
        _ = c.pthread_mutex_lock(&self.mutex);
        defer _ = c.pthread_mutex_unlock(&self.mutex);
        if (self.stopping) return 0;
        self.request = parsed.value;
        self.requested = true;
        _ = c.pthread_cond_signal(&self.changed);
        return 1;
    }
    fn receive(context: ?*anyopaque, out: [*]u8, capacity: usize) callconv(.c) isize {
        const self = cast(context);
        _ = c.pthread_mutex_lock(&self.mutex);
        defer _ = c.pthread_mutex_unlock(&self.mutex);
        if (!self.pending) return -1;
        const response = std.fmt.bufPrint(out[0..capacity], "{{\"type\":\"source\",\"id\":{d},\"epoch\":{d},\"file\":\"{s}\",\"error\":\"{s}\"}}", .{ self.id, self.published_file.epoch, @tagName(self.published_file.load), self.failure }) catch return -1;
        self.pending = false;
        var byte: u8 = 0;
        while (true) {
            const n = c.read(self.wake[0], &byte, 1);
            if (n == 1 or std.posix.errno(n) != .INTR) break;
        }
        return @intCast(response.len);
    }
    fn borrow(context: ?*anyopaque, id: u32, length: *usize) callconv(.c) ?[*]const u8 {
        const self = cast(context);
        _ = c.pthread_mutex_lock(&self.mutex);
        if (id != self.id or id == self.taken or self.failure.len > 0) {
            _ = c.pthread_mutex_unlock(&self.mutex);
            return null;
        }
        self.taken = id;
        length.* = self.length;
        return &self.published;
    }
    fn release(context: ?*anyopaque) callconv(.c) void {
        _ = c.pthread_mutex_unlock(&cast(context).mutex);
    }
    fn read(self: *Loader, request: Request, out: []u8) ![]u8 {
        var path: [2048]u8 = undefined;
        const filename = try std.fmt.bufPrintZ(&path, "{s}/{s}.js", .{ self.directory, @tagName(request.load) });
        const file = c.fopen(filename, "rb") orelse return error.FileNotFound;
        defer _ = c.fclose(file);
        const length = c.fread(out.ptr, 1, out.len, file);
        if (c.ferror(file) != 0) return error.ReadFailed;
        if (length == out.len) return error.SourceTooLarge;
        if (!std.unicode.utf8ValidateSlice(out[0..length])) return error.InvalidUtf8;
        return out[0..length];
    }
    fn run(self: *Loader) void {
        var buffer: [limit]u8 = undefined;
        var last_hash: ?u64 = null;
        while (true) {
            _ = c.pthread_mutex_lock(&self.mutex);
            while (!self.stopping and !self.requested and !self.watching) {
                _ = c.pthread_cond_wait(&self.changed, &self.mutex);
            }
            if (self.stopping) {
                _ = c.pthread_mutex_unlock(&self.mutex);
                return;
            }
            const explicit = self.requested;
            if (explicit) {
                self.selected = self.request;
                self.watching = self.request.watch;
                self.requested = false;
            }
            if (self.selected.load == .clear) {
                self.watching = false;
                _ = c.pthread_mutex_unlock(&self.mutex);
                continue;
            }
            const request = self.selected;
            _ = c.pthread_mutex_unlock(&self.mutex);
            var failure: []const u8 = "";
            const source = self.read(request, &buffer) catch |err| blk: {
                failure = @errorName(err);
                break :blk buffer[0..0];
            };
            const hash = std.hash.Wyhash.hash(0, if (failure.len > 0) failure else source);
            _ = c.pthread_mutex_lock(&self.mutex);
            if (explicit or last_hash == null or hash != last_hash.?) {
                self.published_file = request;
                self.length = source.len;
                @memcpy(self.published[0..source.len], source);
                self.failure = failure;
                self.id +%= 1;
                if (self.id == 0) self.id = 1;
                if (!self.pending) {
                    self.pending = true;
                    const byte: u8 = 1;
                    while (true) {
                        const n = c.write(self.wake[1], &byte, 1);
                        if (n == 1 or std.posix.errno(n) != .INTR) break;
                    }
                }
                last_hash = hash;
            }
            if (self.watching and !self.requested and !self.stopping) {
                var deadline: c.timespec = undefined;
                _ = c.clock_gettime(c.CLOCK_REALTIME, &deadline);
                deadline.tv_nsec += 500_000_000;
                deadline.tv_sec += @divTrunc(deadline.tv_nsec, 1_000_000_000);
                deadline.tv_nsec = @mod(deadline.tv_nsec, 1_000_000_000);
                _ = c.pthread_cond_timedwait(&self.changed, &self.mutex, &deadline);
            }
            _ = c.pthread_mutex_unlock(&self.mutex);
        }
    }
};
