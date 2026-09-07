const std = @import("std");
const runtime = @import("quicktui");
const c = @cImport({
    @cInclude("pthread.h");
    @cInclude("unistd.h");
    @cInclude("fcntl.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("sys/stat.h");
});
const allocator = std.heap.c_allocator;
pub const limit = 64 * 1024;
const Request = struct { op: enum { info, load, begin, append, save, gif }, path: []const u8 = "", text: []const u8 = "", overwrite: bool = false, width: usize = 960 };
pub const Worker = struct {
    enable_gif: bool = false,
    initial_path: []const u8 = "",
    mutex: c.pthread_mutex_t = undefined,
    changed: c.pthread_cond_t = undefined,
    wake: [2]c_int = .{ -1, -1 },
    thread: ?std.Thread = null,
    stopping: bool = false,
    busy: bool = false,
    command: [4096]u8 = undefined,
    command_len: usize = 0,
    reply: [4096]u8 = undefined,
    reply_len: usize = 0,
    data: [limit + 1]u8 = undefined,
    length: usize = 0,
    upload: [limit]u8 = undefined,
    upload_len: usize = 0,
    uploading: bool = false,
    id: u32 = 0,
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
        _ = c.pthread_cond_signal(&self.changed);
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
    fn send(context: ?*anyopaque, bytes: [*]const u8, length: usize) callconv(.c) c_int {
        const self = cast(context);
        if (length > self.command.len) return 0;
        _ = c.pthread_mutex_lock(&self.mutex);
        defer _ = c.pthread_mutex_unlock(&self.mutex);
        if (self.busy or self.stopping) return 0;
        @memcpy(self.command[0..length], bytes[0..length]);
        self.command_len = length;
        self.busy = true;
        _ = c.pthread_cond_signal(&self.changed);
        return 1;
    }
    fn receive(context: ?*anyopaque, out: [*]u8, capacity: usize) callconv(.c) isize {
        const self = cast(context);
        _ = c.pthread_mutex_lock(&self.mutex);
        defer _ = c.pthread_mutex_unlock(&self.mutex);
        if (self.reply_len == 0 or self.reply_len > capacity) return -1;
        const length = self.reply_len;
        @memcpy(out[0..length], self.reply[0..length]);
        self.reply_len = 0;
        self.busy = false;
        var byte: u8 = 0;
        _ = c.read(self.wake[0], &byte, 1);
        return @intCast(length);
    }
    fn borrow(context: ?*anyopaque, id: u32, length: *usize) callconv(.c) ?[*]const u8 {
        const self = cast(context);
        _ = c.pthread_mutex_lock(&self.mutex);
        if (self.busy or id != self.id or id == 0) {
            _ = c.pthread_mutex_unlock(&self.mutex);
            return null;
        }
        length.* = self.length;
        return &self.data;
    }
    fn release(context: ?*anyopaque) callconv(.c) void {
        _ = c.pthread_mutex_unlock(&cast(context).mutex);
    }
    fn perform(self: *Worker, request: Request) !void {
        switch (request.op) {
            .info => {},
            .begin => {
                self.upload_len = 0;
                self.uploading = true;
            },
            .append => {
                if (!self.uploading or request.text.len > limit - self.upload_len) return error.TextTooLarge;
                @memcpy(self.upload[self.upload_len..][0..request.text.len], request.text);
                self.upload_len += request.text.len;
            },
            .load, .save, .gif => {
                if (request.op == .gif and !self.enable_gif) return error.UnsupportedOperation;
                if (request.path.len == 0 or std.mem.indexOfScalar(u8, request.path, 0) != null) return error.InvalidPath;
                var pathbuf: [2048]u8 = undefined;
                const path = try std.fmt.bufPrintZ(&pathbuf, "{s}", .{request.path});
                if (request.op == .load) {
                    const fd = c.open(path, c.O_RDONLY | c.O_NONBLOCK);
                    if (fd < 0) return error.OpenFailed;
                    var stat: c.struct_stat = undefined;
                    if (c.fstat(fd, &stat) != 0 or (stat.st_mode & c.S_IFMT) != c.S_IFREG) {
                        _ = c.close(fd);
                        return error.NotRegularFile;
                    }
                    const file = c.fdopen(fd, "rb") orelse {
                        _ = c.close(fd);
                        return error.OpenFailed;
                    };
                    defer _ = c.fclose(file);
                    self.length = c.fread(&self.data, 1, self.data.len, file);
                    if (c.ferror(file) != 0) return error.ReadFailed;
                    if (self.length > limit) return error.TextTooLarge;
                    const text = self.data[0..self.length];
                    if (!std.unicode.utf8ValidateSlice(text) or std.mem.indexOfScalar(u8, text, 0) != null) return error.NotUtf8Text;
                    self.id +%= 1;
                    if (self.id == 0) self.id = 1;
                } else {
                    if (!self.uploading) return error.NoUpload;
                    const encoded = if (request.op == .gif) try @import("paint_gif.zig").encode(self.upload[0..self.upload_len], request.width) else null;
                    defer if (encoded) |bytes| allocator.free(bytes);
                    const contents = encoded orelse self.upload[0..self.upload_len];
                    if (!std.unicode.utf8ValidateSlice(self.upload[0..self.upload_len])) return error.NotUtf8Text;
                    var stat: c.struct_stat = undefined;
                    const exists = c.lstat(path, &stat) == 0;
                    if (exists and !request.overwrite) return error.FileExists;
                    if (exists and (stat.st_mode & c.S_IFMT) != c.S_IFREG) return error.NotRegularFile;
                    var tmpbuf: [2100]u8 = undefined;
                    const temp = try std.fmt.bufPrintZ(&tmpbuf, "{s}.save-XXXXXX", .{path});
                    const fd = c.mkstemp(temp);
                    if (fd < 0) return error.SaveFailed;
                    defer _ = c.unlink(temp);
                    const file = c.fdopen(fd, "wb") orelse {
                        _ = c.close(fd);
                        return error.SaveFailed;
                    };
                    var closed = false;
                    defer if (!closed) {
                        _ = c.fclose(file);
                    };
                    if (exists and c.fchmod(fd, stat.st_mode & 0o777) != 0) return error.SaveFailed;
                    if (c.fwrite(contents.ptr, 1, contents.len, file) != contents.len or c.fflush(file) != 0 or c.fsync(fd) != 0) return error.SaveFailed;
                    const result = c.fclose(file);
                    closed = true;
                    if (result != 0) return error.SaveFailed;
                    // Link prevents a racing new file from being overwritten without approval.
                    if (request.overwrite) {
                        if (c.rename(temp, path) != 0) return error.SaveFailed;
                    } else if (c.link(temp, path) != 0) return error.FileExists;
                    self.uploading = false;
                }
            },
        }
    }
    fn run(self: *Worker) void {
        while (true) {
            _ = c.pthread_mutex_lock(&self.mutex);
            while (!self.stopping and self.command_len == 0) {
                _ = c.pthread_cond_wait(&self.changed, &self.mutex);
            }
            if (self.stopping) {
                _ = c.pthread_mutex_unlock(&self.mutex);
                return;
            }
            var command: [4096]u8 = undefined;
            const length = self.command_len;
            @memcpy(command[0..length], self.command[0..length]);
            self.command_len = 0;
            _ = c.pthread_mutex_unlock(&self.mutex);
            const parsed = std.json.parseFromSlice(Request, allocator, command[0..length], .{}) catch {
                self.publish("InvalidRequest", "error");
                continue;
            };
            defer parsed.deinit();
            self.perform(parsed.value) catch |err| {
                self.publish(@errorName(err), @tagName(parsed.value.op));
                continue;
            };
            self.publish("", @tagName(parsed.value.op));
        }
    }
    fn publish(self: *Worker, failure: []const u8, op: []const u8) void {
        _ = c.pthread_mutex_lock(&self.mutex);
        defer _ = c.pthread_mutex_unlock(&self.mutex);
        const reply = std.json.Stringify.valueAlloc(allocator, .{ .op = op, .@"error" = failure, .id = self.id, .path = self.initial_path }, .{}) catch unreachable;
        defer allocator.free(reply);
        if (reply.len > self.reply.len) unreachable;
        @memcpy(self.reply[0..reply.len], reply);
        self.reply_len = reply.len;
        const byte: u8 = 1;
        _ = c.write(self.wake[1], &byte, 1);
    }
};

test "editor saves UTF-8 atomically and protects existing files" {
    var template = "/tmp/quicktui-editor-XXXXXX".*;
    const directory = c.mkdtemp(&template) orelse return error.TempFailed;
    defer _ = c.rmdir(directory);
    var pathbuf: [1024]u8 = undefined;
    const path = try std.fmt.bufPrintZ(&pathbuf, "{s}/notes.txt", .{std.mem.span(directory)});
    defer _ = c.unlink(path);
    var worker: Worker = .{};
    try worker.perform(.{ .op = .begin });
    try worker.perform(.{ .op = .append, .text = "Hello café\n" });
    try worker.perform(.{ .op = .save, .path = path });
    try worker.perform(.{ .op = .load, .path = path });
    try std.testing.expectEqualStrings("Hello café\n", worker.data[0..worker.length]);
    try worker.perform(.{ .op = .begin });
    try worker.perform(.{ .op = .append, .text = "Replacement" });
    try std.testing.expectError(error.FileExists, worker.perform(.{ .op = .save, .path = path }));
    try worker.perform(.{ .op = .load, .path = path });
    try std.testing.expectEqualStrings("Hello café\n", worker.data[0..worker.length]);
    try worker.perform(.{ .op = .save, .path = path, .overwrite = true });
    try worker.perform(.{ .op = .load, .path = path });
    try std.testing.expectEqualStrings("Replacement", worker.data[0..worker.length]);
    try worker.perform(.{ .op = .begin });
    try worker.perform(.{ .op = .save, .path = path, .overwrite = true });
    try worker.perform(.{ .op = .load, .path = path });
    try std.testing.expectEqual(0, worker.length);
    try std.testing.expectError(error.InvalidPath, worker.perform(.{ .op = .load, .path = "bad\x00path" }));
    worker.uploading = true;
    worker.upload_len = limit;
    try std.testing.expectError(error.TextTooLarge, worker.perform(.{ .op = .append, .text = "x" }));
}
