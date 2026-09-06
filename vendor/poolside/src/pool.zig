// SPDX-License-Identifier: MPL-2.0

//! Stable, chunked storage addressed by generational handles.
//!
//! A pool allocates whole chunks as capacity grows and reuses ended slots
//! through a free list. Access, take, discard, iteration, and clearing do not
//! allocate. Ending an object never frees its chunk; `deinit` releases retained
//! storage. Poolside never calls a method on a stored value.

const std = @import("std");
const builtin = @import("builtin");

/// Compile-time storage, generation, and diagnostic configuration.
pub const Options = struct {
    /// Slots per independently allocated chunk. Slot addresses never move.
    chunk_len: usize = 512,
    /// Object-generation width. Smaller counters exhaust and retire sooner.
    generation_bits: u16 = 32,
    /// Source locations increase slot size substantially, so default to Debug.
    track_provenance: bool = builtin.mode == .Debug,
};

/// Creates a pool with default options and handles branded by `T`.
pub fn Pool(comptime T: type) type {
    return PoolWithOptions(T, .{});
}

/// Creates a pool with custom chunk, generation, and provenance options.
pub fn PoolWithOptions(comptime T: type, comptime options: Options) type {
    return PoolImpl(T, T, options);
}

/// Creates a pool whose handles are branded with `Tag`. Use distinct tags when
/// a program has multiple pools of the same value type and wants the compiler
/// to reject accidentally mixing their handles.
pub fn TaggedPool(comptime T: type, comptime Tag: type) type {
    return TaggedPoolWithOptions(T, Tag, .{});
}

/// Creates a tagged pool with custom options.
pub fn TaggedPoolWithOptions(comptime T: type, comptime Tag: type, comptime options: Options) type {
    return PoolImpl(T, Tag, options);
}

fn PoolImpl(comptime T: type, comptime Tag: type, comptime options: Options) type {
    comptime {
        if (options.chunk_len == 0) @compileError("poolside chunk_len must be greater than zero");
        if (options.generation_bits < 2 or options.generation_bits > 64) {
            @compileError("poolside generation_bits must be between 2 and 64");
        }
    }

    const GenerationType = std.meta.Int(.unsigned, options.generation_bits);

    return struct {
        const Self = @This();
        const none_index = std.math.maxInt(u32);
        const Provenance = if (options.track_provenance) ?std.builtin.SourceLocation else void;

        /// The stored payload type.
        pub const Value = T;
        /// The type this pool's handles are branded with.
        pub const PoolTag = Tag;
        /// The object-generation integer, sized by `generation_bits`.
        pub const Generation = GenerationType;
        /// The options this pool type was instantiated with.
        pub const config = options;
        /// Capacity growth may return an allocator error. `OutOfCapacity`
        /// means every 32-bit slot index has been introduced.
        pub const CreateError = std.mem.Allocator.Error || error{OutOfCapacity};

        /// Identifies one object lifetime. Reusing a slot changes its
        /// generation, so a handle cannot resolve to a later occupant.
        pub const Handle = packed struct {
            index: u32,
            generation: Generation,

            /// Sentinel for an absent handle. It never resolves to a value.
            pub const none: Handle = .{ .index = none_index, .generation = 0 };

            /// Returns whether this is the `none` sentinel.
            pub fn isNone(handle: Handle) bool {
                return handle.index == none_index;
            }

            /// Compares both slot index and object generation.
            pub fn eql(a: Handle, b: Handle) bool {
                return a.index == b.index and a.generation == b.generation;
            }
        };

        const Slot = struct {
            generation: Generation,
            free_next: u32,
            born_at: Provenance,
            ended_at: Provenance,
            value: T,
        };

        const Chunk = [options.chunk_len]Slot;

        allocator: std.mem.Allocator,
        chunks: std.ArrayList(*Chunk) = .empty,
        pointer_lock: std.debug.SafetyLock = .{},
        slot_count: u32 = 0,
        free_head: u32 = none_index,
        live_count: u32 = 0,
        retired_count: u32 = 0,

        /// Initializes an empty pool without allocating.
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        /// Releases the pool's own storage. Live payloads are discarded
        /// without being read, so callers owning resources must clean them
        /// before calling this.
        pub fn deinit(self: *Self) void {
            self.pointer_lock.assertUnlocked();
            for (self.chunks.items) |chunk| self.allocator.destroy(chunk);
            self.chunks.deinit(self.allocator);
            self.* = undefined;
        }

        /// Stores `value` in a free slot or grows by one chunk. Reusing a slot
        /// does not allocate. On error the pool has not accepted `value`.
        pub fn create(self: *Self, value: T) CreateError!Handle {
            return self.createImpl(value, null);
        }

        /// Like `create`, recording `source` as the creation site when
        /// provenance is enabled.
        pub fn createAt(self: *Self, value: T, source: std.builtin.SourceLocation) CreateError!Handle {
            return self.createImpl(value, source);
        }

        fn createImpl(self: *Self, value: T, source: ?std.builtin.SourceLocation) CreateError!Handle {
            if (self.free_head != none_index) {
                const index = self.free_head;
                const current = self.slot(index);
                self.free_head = current.free_next;
                std.debug.assert(current.generation != 0);
                std.debug.assert(!isLiveGeneration(current.generation));
                current.generation +%= 1;
                std.debug.assert(isLiveGeneration(current.generation));
                current.value = value;
                if (options.track_provenance) current.born_at = source;
                self.live_count += 1;
                return .{ .index = index, .generation = current.generation };
            }
            return self.createFresh(value, source);
        }

        fn createFresh(self: *Self, value: T, source: ?std.builtin.SourceLocation) CreateError!Handle {
            if (self.slot_count == none_index) return error.OutOfCapacity;

            const index = self.slot_count;
            const index_usize: usize = @intCast(index);
            const chunk_index = index_usize / options.chunk_len;
            if (chunk_index == self.chunks.items.len) {
                const chunk = try self.allocator.create(Chunk);
                errdefer self.allocator.destroy(chunk);
                try self.chunks.append(self.allocator, chunk);
            }

            self.slot_count += 1;
            self.live_count += 1;
            self.slot(index).* = .{
                .generation = 1,
                .free_next = none_index,
                .born_at = if (options.track_provenance) source else {},
                .ended_at = if (options.track_provenance) null else {},
                .value = value,
            };
            return .{ .index = index, .generation = 1 };
        }

        /// Transfers the stored payload out of the pool and ends the object's
        /// lifetime. Stale, forged, and already-ended handles return null and
        /// change nothing. A generation that wraps to zero retires its slot.
        ///
        /// The returned value belongs to the caller. Poolside never calls a
        /// method on `T`, so a payload owning resources must be cleaned up by
        /// the caller with the allocator and context that created them.
        pub fn take(self: *Self, handle: Handle) ?T {
            return self.takeImpl(handle, null);
        }

        /// Like `take`, recording `source` as the end-of-lifetime site when
        /// provenance is enabled.
        pub fn takeAt(self: *Self, handle: Handle, source: std.builtin.SourceLocation) ?T {
            return self.takeImpl(handle, source);
        }

        fn takeImpl(self: *Self, handle: Handle, source: ?std.builtin.SourceLocation) ?T {
            self.pointer_lock.assertUnlocked();
            const current = self.liveSlot(handle) orelse return null;
            const taken = current.value;
            current.value = undefined;
            self.endLifetime(handle.index, current, source);
            return taken;
        }

        /// Ends an object's lifetime without reading its payload. Use it for
        /// plain values, or after cleaning a value in place through `get`,
        /// whose cleanup method may leave the value undefined.
        pub fn discard(self: *Self, handle: Handle) bool {
            return self.discardImpl(handle, null);
        }

        /// Like `discard`, recording `source` as the end-of-lifetime site when
        /// provenance is enabled.
        pub fn discardAt(self: *Self, handle: Handle, source: std.builtin.SourceLocation) bool {
            return self.discardImpl(handle, source);
        }

        fn discardImpl(self: *Self, handle: Handle, source: ?std.builtin.SourceLocation) bool {
            self.pointer_lock.assertUnlocked();
            const current = self.liveSlot(handle) orelse return false;
            current.value = undefined;
            self.endLifetime(handle.index, current, source);
            return true;
        }

        /// Advances the generation and performs the count, provenance,
        /// retirement, and free-list transitions shared by take and discard.
        fn endLifetime(
            self: *Self,
            index: u32,
            current: *Slot,
            source: ?std.builtin.SourceLocation,
        ) void {
            current.generation +%= 1;
            self.live_count -= 1;
            if (options.track_provenance) current.ended_at = source;

            if (current.generation == 0) {
                current.free_next = none_index;
                self.retired_count += 1;
            } else {
                std.debug.assert(!isLiveGeneration(current.generation));
                current.free_next = self.free_head;
                self.free_head = index;
            }
        }

        /// Rejects pointer-invalidating operations until `unlockPointers`.
        /// Bracket the lifetime of a pointer returned by an accessor or
        /// iterator to get a Debug and ReleaseSafe diagnostic instead of
        /// silent use-after-invalidation. The guard protects addresses, not
        /// iterator completeness, which remains a documented caller rule.
        /// The lock is opt-in, not nestable, and compiles out in ReleaseFast
        /// and ReleaseSmall.
        pub fn lockPointers(self: *Self) void {
            self.pointer_lock.lock();
        }

        /// Ends the pointer guard started by `lockPointers`.
        pub fn unlockPointers(self: *Self) void {
            self.pointer_lock.unlock();
        }

        /// Returns whether `handle` names its original live object.
        pub fn contains(self: *const Self, handle: Handle) bool {
            return self.liveSlotConst(handle) != null;
        }

        /// Returns a stable pointer while `handle` remains live. The caller
        /// must obey the pointer lifetime rules documented by `lockPointers`.
        pub fn get(self: *Self, handle: Handle) ?*T {
            const current = self.liveSlot(handle) orelse return null;
            return &current.value;
        }

        /// Const form of `get`.
        pub fn getConst(self: *const Self, handle: Handle) ?*const T {
            const current = self.liveSlotConst(handle) orelse return null;
            return &current.value;
        }

        /// Returns the live value pointer or panics with stale-handle
        /// diagnostics when the handle does not resolve.
        pub fn expect(self: *Self, handle: Handle) *T {
            return self.get(handle) orelse self.stale(handle);
        }

        /// Const form of `expect`.
        pub fn expectConst(self: *const Self, handle: Handle) *const T {
            return self.getConst(handle) orelse self.stale(handle);
        }

        /// Slot-oriented creation and end-of-lifetime diagnostics.
        pub const ProvenanceInfo = struct {
            current_generation: Generation,
            live: bool,
            born_at: ?std.builtin.SourceLocation,
            ended_at: ?std.builtin.SourceLocation,
        };

        /// Returns diagnostics for the handle's slot when provenance is
        /// enabled. For a stale handle, the metadata describes the slot's
        /// current occupant and the most recently recorded end of lifetime.
        pub fn provenance(self: *const Self, handle: Handle) ?ProvenanceInfo {
            if (!options.track_provenance or handle.isNone() or handle.index >= self.slot_count) return null;
            const current = self.slotConst(handle.index);
            return .{
                .current_generation = current.generation,
                .live = isLiveGeneration(current.generation),
                .born_at = current.born_at,
                .ended_at = current.ended_at,
            };
        }

        fn stale(self: *const Self, handle: Handle) noreturn {
            if (options.track_provenance and !handle.isNone() and handle.index < self.slot_count) {
                const current = self.slotConst(handle.index);
                if (current.ended_at) |source| {
                    std.debug.panic(
                        "stale poolside handle {d}/{d}; object lifetime ended at {s}:{d}:{d} in {s}",
                        .{ handle.index, handle.generation, source.file, source.line, source.column, source.fn_name },
                    );
                }
            }
            std.debug.panic("stale poolside handle {d}/{d}", .{ handle.index, handle.generation });
        }

        /// Invalidates every live handle and discards the stored payload bits
        /// without reading them, retaining allocated chunks. Exhausted
        /// generations are retired, not recycled.
        pub fn clearRetainingCapacity(self: *Self) void {
            self.clearImpl(null);
        }

        /// Like `clearRetainingCapacity`, recording `source` for every live
        /// object whose lifetime ends when provenance is enabled.
        pub fn clearRetainingCapacityAt(self: *Self, source: std.builtin.SourceLocation) void {
            self.clearImpl(source);
        }

        fn clearImpl(self: *Self, source: ?std.builtin.SourceLocation) void {
            self.pointer_lock.assertUnlocked();
            self.free_head = none_index;
            self.live_count = 0;
            self.retired_count = 0;

            var index = self.slot_count;
            while (index > 0) {
                index -= 1;
                const current = self.slot(index);
                if (isLiveGeneration(current.generation)) {
                    current.value = undefined;
                    current.generation +%= 1;
                    if (options.track_provenance) current.ended_at = source;
                }
                if (current.generation == 0) {
                    current.free_next = none_index;
                    self.retired_count += 1;
                } else {
                    current.free_next = self.free_head;
                    self.free_head = index;
                }
            }
        }

        /// One live object: its handle and a pointer to its value.
        pub const Entry = struct {
            handle: Handle,
            value: *T,
        };

        /// Walks live slots in index order, skipping free and retired ones.
        pub const Iterator = struct {
            pool: *Self,
            next_index: u32 = 0,

            /// Returns the next live entry, or null at the end.
            pub fn next(iter: *Iterator) ?Entry {
                while (iter.next_index < iter.pool.slot_count) {
                    const index = iter.next_index;
                    iter.next_index += 1;
                    const current = iter.pool.slot(index);
                    if (isLiveGeneration(current.generation)) {
                        return .{
                            .handle = .{ .index = index, .generation = current.generation },
                            .value = &current.value,
                        };
                    }
                }
                return null;
            }
        };

        /// Iterates over live values and mutable pointers. Mutation of the pool
        /// while an iterator is active follows the contract in the README.
        pub fn iterator(self: *Self) Iterator {
            return .{ .pool = self };
        }

        /// Const form of `Entry`.
        pub const ConstEntry = struct {
            handle: Handle,
            value: *const T,
        };

        /// Const form of `Iterator`.
        pub const ConstIterator = struct {
            pool: *const Self,
            next_index: u32 = 0,

            /// Returns the next live entry, or null at the end.
            pub fn next(iter: *ConstIterator) ?ConstEntry {
                while (iter.next_index < iter.pool.slot_count) {
                    const index = iter.next_index;
                    iter.next_index += 1;
                    const current = iter.pool.slotConst(index);
                    if (isLiveGeneration(current.generation)) {
                        return .{
                            .handle = .{ .index = index, .generation = current.generation },
                            .value = &current.value,
                        };
                    }
                }
                return null;
            }
        };

        /// Const form of `iterator`.
        pub fn constIterator(self: *const Self) ConstIterator {
            return .{ .pool = self };
        }

        /// Number of currently live objects.
        pub fn liveCount(self: *const Self) u32 {
            return self.live_count;
        }

        /// Number of slots ever introduced, including free and retired slots.
        pub fn slotCount(self: *const Self) u32 {
            return self.slot_count;
        }

        /// Number of slots permanently retired after generation exhaustion.
        pub fn retiredCount(self: *const Self) u32 {
            return self.retired_count;
        }

        fn slot(self: *Self, index: u32) *Slot {
            const i: usize = @intCast(index);
            return &self.chunks.items[i / options.chunk_len][i % options.chunk_len];
        }

        fn slotConst(self: *const Self, index: u32) *const Slot {
            const i: usize = @intCast(index);
            return &self.chunks.items[i / options.chunk_len][i % options.chunk_len];
        }

        fn liveSlot(self: *Self, handle: Handle) ?*Slot {
            if (handle.isNone() or handle.index >= self.slot_count) return null;
            const current = self.slot(handle.index);
            if (!isLiveGeneration(current.generation) or current.generation != handle.generation) return null;
            return current;
        }

        fn liveSlotConst(self: *const Self, handle: Handle) ?*const Slot {
            if (handle.isNone() or handle.index >= self.slot_count) return null;
            const current = self.slotConst(handle.index);
            if (!isLiveGeneration(current.generation) or current.generation != handle.generation) return null;
            return current;
        }

        fn isLiveGeneration(generation: Generation) bool {
            return generation & 1 == 1;
        }
    };
}

const testing = std.testing;

/// Payload that owns a resource and counts explicit cleanups. Poolside must
/// never call `deinit`, so every counted cleanup below is one the test made.
const CountedResource = struct {
    data: []u8,
    cleanups: *usize,

    fn init(allocator: std.mem.Allocator, cleanups: *usize) !CountedResource {
        return .{ .data = try allocator.alloc(u8, 4), .cleanups = cleanups };
    }

    pub fn deinit(self: *CountedResource, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        self.cleanups.* += 1;
        self.* = undefined;
    }
};

test "create, mutate, take, and reuse reject stale handles" {
    const P = Pool(u64);
    var pool = P.init(testing.allocator);
    defer pool.deinit();

    const first = try pool.create(10);
    try testing.expectEqual(@as(usize, 8), @sizeOf(P.Handle));
    try testing.expect(pool.contains(first));
    try testing.expectEqual(@as(u64, 10), pool.getConst(first).?.*);
    pool.expect(first).* = 20;
    try testing.expectEqual(@as(u64, 20), pool.expectConst(first).*);

    try testing.expectEqual(@as(?u64, 20), pool.take(first));
    try testing.expect(pool.take(first) == null);
    try testing.expect(!pool.discard(first));
    try testing.expect(pool.get(first) == null);
    try testing.expectEqual(@as(u32, 0), pool.liveCount());

    const second = try pool.create(30);
    try testing.expectEqual(first.index, second.index);
    try testing.expect(first.generation != second.generation);
    try testing.expect(pool.get(first) == null);
    try testing.expectEqual(@as(u64, 30), pool.expect(second).*);
    try testing.expect(pool.discard(second));
    try testing.expectEqual(@as(u32, 0), pool.liveCount());
}

test "take transfers a resource-owning payload exactly once" {
    var cleanups: usize = 0;
    var pool = Pool(CountedResource).init(testing.allocator);
    defer pool.deinit();

    const handle = try pool.create(try CountedResource.init(testing.allocator, &cleanups));
    try testing.expectEqual(@as(u32, 1), pool.liveCount());

    var taken = pool.take(handle).?;
    taken.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), cleanups);
    try testing.expectEqual(@as(u32, 0), pool.liveCount());

    // A stale take cannot produce a second value to clean up.
    try testing.expect(pool.take(handle) == null);
    try testing.expectEqual(@as(usize, 1), cleanups);
}

test "discard succeeds after an in-place cleanup leaves the value undefined" {
    var cleanups: usize = 0;
    var pool = Pool(CountedResource).init(testing.allocator);
    defer pool.deinit();

    const handle = try pool.create(try CountedResource.init(testing.allocator, &cleanups));
    pool.get(handle).?.deinit(testing.allocator);
    try testing.expect(pool.discard(handle));
    try testing.expectEqual(@as(usize, 1), cleanups);
    try testing.expect(pool.get(handle) == null);
    try testing.expect(!pool.discard(handle));

    // The slot is reusable after an in-place cleanup.
    const reused = try pool.create(try CountedResource.init(testing.allocator, &cleanups));
    try testing.expectEqual(handle.index, reused.index);
    var taken = pool.take(reused).?;
    taken.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 2), cleanups);
}

test "poolside calls no payload method during take, discard, clear, or deinit" {
    var cleanups: usize = 0;
    var pool = Pool(CountedResource).init(testing.allocator);

    const taken_handle = try pool.create(try CountedResource.init(testing.allocator, &cleanups));
    const discarded_handle = try pool.create(try CountedResource.init(testing.allocator, &cleanups));

    var taken = pool.take(taken_handle).?;
    try testing.expectEqual(@as(usize, 0), cleanups);
    taken.deinit(testing.allocator);

    pool.get(discarded_handle).?.deinit(testing.allocator);
    try testing.expect(pool.discard(discarded_handle));
    try testing.expectEqual(@as(usize, 2), cleanups);

    const cleared_handle = try pool.create(try CountedResource.init(testing.allocator, &cleanups));
    pool.get(cleared_handle).?.deinit(testing.allocator);
    pool.clearRetainingCapacity();
    try testing.expectEqual(@as(usize, 3), cleanups);

    const remaining = try pool.create(try CountedResource.init(testing.allocator, &cleanups));
    pool.get(remaining).?.deinit(testing.allocator);
    pool.deinit();
    try testing.expectEqual(@as(usize, 4), cleanups);
}

test "failed creation leaves payload ownership with the caller" {
    var cleanups: usize = 0;
    var failing = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    var pool = Pool(CountedResource).init(failing.allocator());
    defer pool.deinit();

    var value = try CountedResource.init(testing.allocator, &cleanups);
    try testing.expectError(error.OutOfMemory, pool.create(value));
    try testing.expectEqual(@as(usize, 0), cleanups);
    try testing.expectEqual(@as(u32, 0), pool.liveCount());
    try testing.expectEqual(@as(u32, 0), pool.slotCount());

    value.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), cleanups);
}

test "payload declarations named deinit are never inspected" {
    // Neither declaration matches the signatures the pool once required, so
    // instantiating these pools proves the pool no longer looks at them.
    const OddSignature = struct {
        value: u32,

        pub fn deinit(self: @This(), first: u32, second: u32) u64 {
            return self.value + first + second;
        }
    };
    const NotAFunction = struct {
        value: u32,

        pub const deinit = 42;
    };

    var odd = Pool(OddSignature).init(testing.allocator);
    defer odd.deinit();
    const odd_handle = try odd.create(.{ .value = 1 });
    try testing.expectEqual(@as(u32, 1), odd.take(odd_handle).?.value);

    var plain = Pool(NotAFunction).init(testing.allocator);
    defer plain.deinit();
    const plain_handle = try plain.create(.{ .value = 2 });
    try testing.expect(plain.discard(plain_handle));
}

test "take, discard, and clear perform no allocation" {
    var failing = std.testing.FailingAllocator.init(testing.allocator, .{});
    const P = PoolWithOptions(u64, .{ .chunk_len = 4 });
    var pool = P.init(failing.allocator());
    defer pool.deinit();

    var handles: [8]P.Handle = undefined;
    for (&handles, 0..) |*handle, i| handle.* = try pool.create(@intCast(i));
    const allocations = failing.allocations;
    try testing.expect(allocations > 0);

    for (handles[0..4], 0..) |handle, i| {
        try testing.expectEqual(@as(?u64, @intCast(i)), pool.take(handle));
    }
    for (handles[4..]) |handle| try testing.expect(pool.discard(handle));
    pool.clearRetainingCapacity();
    try testing.expectEqual(allocations, failing.allocations);
}

test "tagged pools give same-value pools distinct handle types" {
    const FirstTag = struct {};
    const SecondTag = struct {};
    const First = TaggedPool(u32, FirstTag);
    const Second = TaggedPool(u32, SecondTag);
    comptime std.debug.assert(First.Handle != Second.Handle);
}

test "two pools of the same type can issue identical handle bits" {
    // Documented limitation: tags separate pool types and roles, not runtime
    // pool values. A handle must be returned to the pool value that issued it.
    const P = Pool(u32);
    var first = P.init(testing.allocator);
    defer first.deinit();
    var second = P.init(testing.allocator);
    defer second.deinit();

    const from_first = try first.create(1);
    const from_second = try second.create(2);
    try testing.expect(from_first.eql(from_second));

    // The wrong pool cannot detect the mix, so it answers for its own slot.
    try testing.expectEqual(@as(u32, 2), second.expect(from_first).*);
    try testing.expect(first.contains(from_second));
    try testing.expectEqual(@as(?u32, 1), first.take(from_second));
}

test "explicit provenance records creation and end of lifetime" {
    const P = PoolWithOptions(u8, .{ .track_provenance = true });
    var pool = P.init(testing.allocator);
    defer pool.deinit();

    const born = @src();
    const handle = try pool.createAt(1, born);
    const live_info = pool.provenance(handle).?;
    try testing.expect(live_info.live);
    try testing.expectEqual(born.line, live_info.born_at.?.line);
    try testing.expect(live_info.ended_at == null);

    const taken_at = @src();
    try testing.expectEqual(@as(?u8, 1), pool.takeAt(handle, taken_at));
    const dead_info = pool.provenance(handle).?;
    try testing.expect(!dead_info.live);
    try testing.expectEqual(taken_at.line, dead_info.ended_at.?.line);

    const discarded = try pool.createAt(2, @src());
    const discarded_at = @src();
    try testing.expect(pool.discardAt(discarded, discarded_at));
    try testing.expectEqual(discarded_at.line, pool.provenance(discarded).?.ended_at.?.line);

    const cleared = try pool.createAt(3, @src());
    pool.clearRetainingCapacity();
    try testing.expect(pool.provenance(cleared).?.ended_at == null);

    const cleared_at = try pool.createAt(4, @src());
    const clear_source = @src();
    pool.clearRetainingCapacityAt(clear_source);
    try testing.expectEqual(clear_source.line, pool.provenance(cleared_at).?.ended_at.?.line);
}

test "disabled provenance configuration is compiled and returns null" {
    const P = PoolWithOptions(u8, .{ .track_provenance = false });
    var pool = P.init(testing.allocator);
    defer pool.deinit();

    const handle = try pool.createAt(1, @src());
    try testing.expect(pool.provenance(handle) == null);
    try testing.expectEqual(@as(?u8, 1), pool.takeAt(handle, @src()));
    try testing.expect(pool.provenance(handle) == null);

    const discarded = try pool.createAt(2, @src());
    try testing.expect(pool.discardAt(discarded, @src()));
    try testing.expect(pool.provenance(discarded) == null);
}

test "disabled provenance removes its slot metadata" {
    const Tracked = PoolWithOptions(u8, .{ .track_provenance = true });
    const Untracked = PoolWithOptions(u8, .{ .track_provenance = false });

    try testing.expectEqual(@as(usize, 0), @sizeOf(Untracked.Provenance));
    try testing.expect(@sizeOf(Tracked.Provenance) > 0);
    try testing.expect(@sizeOf(Untracked.Slot) < @sizeOf(Tracked.Slot));

    // A u32 generation, a u32 free-list link, and a padded u8 payload.
    try testing.expectEqual(@as(usize, 12), @sizeOf(Untracked.Slot));
}

test "the pointer guard costs no space in unsafe builds" {
    switch (builtin.mode) {
        .ReleaseFast, .ReleaseSmall => {
            try testing.expectEqual(@as(usize, 0), @sizeOf(std.debug.SafetyLock));
            // Applying a 64-bit constant to a 32-bit target would be wrong.
            if (@sizeOf(usize) == 8) {
                try testing.expectEqual(@as(usize, 56), @sizeOf(Pool(u8)));
            }
        },
        .Debug, .ReleaseSafe => try testing.expect(@sizeOf(std.debug.SafetyLock) > 0),
    }
}

test "the pointer lock permits create, access, provenance, and iteration" {
    const P = PoolWithOptions(u32, .{ .chunk_len = 1 });
    var pool = P.init(testing.allocator);
    defer pool.deinit();

    const first = try pool.create(1);
    pool.lockPointers();
    const pointer = pool.expect(first);

    // Creating another chunk does not move an existing slot.
    _ = try pool.create(2);
    try testing.expectEqual(@intFromPtr(pointer), @intFromPtr(pool.get(first).?));
    try testing.expectEqual(@as(u32, 1), pointer.*);
    try testing.expect(pool.contains(first));
    _ = pool.provenance(first);

    var count: usize = 0;
    var entries = pool.iterator();
    while (entries.next()) |_| count += 1;
    try testing.expectEqual(@as(usize, 2), count);
    pool.unlockPointers();

    // Mutation is allowed again once the pointer lifetime is over.
    try testing.expectEqual(@as(?u32, 1), pool.take(first));
    pool.lockPointers();
    pool.unlockPointers();
    pool.clearRetainingCapacity();
}

test "an even-generation forged handle cannot take or discard a free slot" {
    const P = PoolWithOptions(u8, .{ .generation_bits = 8 });
    var pool = P.init(testing.allocator);
    defer pool.deinit();

    const handle = try pool.create(1);
    try testing.expectEqual(@as(?u8, 1), pool.take(handle));
    const forged = P.Handle{ .index = handle.index, .generation = handle.generation +% 1 };
    try testing.expect(!pool.contains(forged));
    try testing.expect(pool.take(forged) == null);
    try testing.expect(!pool.discard(forged));
    try testing.expectEqual(@as(u32, 0), pool.liveCount());
    try testing.expect(pool.get(P.Handle.none) == null);
    try testing.expect(pool.take(P.Handle.none) == null);
    try testing.expect(!pool.discard(.{ .index = 1000, .generation = 1 }));
}

test "generation exhaustion retires a slot before ABA aliasing" {
    const P = PoolWithOptions(u8, .{ .chunk_len = 1, .generation_bits = 2 });
    var pool = P.init(testing.allocator);
    defer pool.deinit();

    const generation_one = try pool.create(1);
    try testing.expectEqual(@as(?u8, 1), pool.take(generation_one));
    const generation_three = try pool.create(2);
    try testing.expectEqual(generation_one.index, generation_three.index);
    try testing.expectEqual(@as(P.Generation, 3), generation_three.generation);
    try testing.expectEqual(@as(?u8, 2), pool.take(generation_three));
    try testing.expectEqual(@as(u32, 1), pool.retiredCount());

    const fresh = try pool.create(3);
    try testing.expect(fresh.index != generation_one.index);
    try testing.expect(pool.get(generation_one) == null);
    try testing.expect(pool.get(generation_three) == null);
}

test "discard retires an exhausted generation" {
    const P = PoolWithOptions(u8, .{ .chunk_len = 1, .generation_bits = 2 });
    var pool = P.init(testing.allocator);
    defer pool.deinit();

    const first = try pool.create(1);
    try testing.expect(pool.discard(first));
    const last_generation = try pool.create(2);
    try testing.expect(pool.discard(last_generation));
    try testing.expectEqual(@as(u32, 1), pool.retiredCount());
    try testing.expectEqual(@as(u32, 0), pool.liveCount());

    const fresh = try pool.create(3);
    try testing.expect(fresh.index != last_generation.index);
}

test "clear retires a generation that wraps" {
    const P = PoolWithOptions(u8, .{ .chunk_len = 1, .generation_bits = 2 });
    var pool = P.init(testing.allocator);
    defer pool.deinit();

    const first = try pool.create(1);
    try testing.expect(pool.discard(first));
    const last_generation = try pool.create(2);
    pool.clearRetainingCapacity();
    try testing.expectEqual(@as(u32, 1), pool.retiredCount());
    try testing.expect(pool.get(last_generation) == null);
    const fresh = try pool.create(3);
    try testing.expect(fresh.index != last_generation.index);
}

test "slot addresses stay stable as the chunk table grows" {
    const P = PoolWithOptions(u64, .{ .chunk_len = 2 });
    var pool = P.init(testing.allocator);
    defer pool.deinit();

    const first = try pool.create(1234);
    const pointer = pool.get(first).?;
    for (0..100) |i| _ = try pool.create(i);
    try testing.expectEqual(@intFromPtr(pointer), @intFromPtr(pool.get(first).?));
    try testing.expectEqual(@as(u64, 1234), pointer.*);
}

test "iterator skips free and retired slots" {
    const P = Pool(u32);
    var pool = P.init(testing.allocator);
    defer pool.deinit();

    const a = try pool.create(1);
    const b = try pool.create(2);
    _ = try pool.create(4);
    try testing.expect(pool.discard(b));

    var sum: u32 = 0;
    var count: usize = 0;
    var entries = pool.iterator();
    while (entries.next()) |entry| {
        try testing.expect(pool.contains(entry.handle));
        sum += entry.value.*;
        count += 1;
    }
    try testing.expectEqual(@as(usize, 2), count);
    try testing.expectEqual(@as(u32, 5), sum);
    try testing.expect(pool.contains(a));

    const const_pool: *const P = &pool;
    var const_sum: u32 = 0;
    var const_count: usize = 0;
    var const_entries = const_pool.constIterator();
    while (const_entries.next()) |entry| {
        const_sum += entry.value.*;
        const_count += 1;
    }
    try testing.expectEqual(count, const_count);
    try testing.expectEqual(sum, const_sum);
}

test "iterating and cleaning before clear is allocation free" {
    // The pattern the documentation recommends for resource-owning payloads.
    var cleanups: usize = 0;
    var pool = Pool(CountedResource).init(testing.allocator);
    defer pool.deinit();

    for (0..4) |_| _ = try pool.create(try CountedResource.init(testing.allocator, &cleanups));

    var entries = pool.iterator();
    while (entries.next()) |entry| entry.value.deinit(testing.allocator);
    pool.clearRetainingCapacity();

    try testing.expectEqual(@as(usize, 4), cleanups);
    try testing.expectEqual(@as(u32, 0), pool.liveCount());
}

test "clearRetainingCapacity invalidates handles without reading payloads" {
    const P = Pool(u32);
    var pool = P.init(testing.allocator);
    defer pool.deinit();

    const a = try pool.create(1);
    const b = try pool.create(2);
    try testing.expectEqual(@as(?u32, 1), pool.take(a));
    pool.clearRetainingCapacity();

    try testing.expect(pool.get(b) == null);
    try testing.expect(pool.take(b) == null);
    try testing.expect(!pool.discard(b));
    try testing.expectEqual(@as(u32, 0), pool.liveCount());

    const reused = try pool.create(3);
    try testing.expectEqual(@as(u32, 3), pool.expect(reused).*);
}

test "clear rebuilds a duplicate-free reusable free list" {
    const P = PoolWithOptions(u16, .{ .chunk_len = 3 });
    var pool = P.init(testing.allocator);
    defer pool.deinit();

    var old: [20]P.Handle = undefined;
    for (&old, 0..) |*handle, i| handle.* = try pool.create(@intCast(i));
    for (old, 0..) |handle, i| {
        if (i % 3 == 0) try testing.expect(pool.discard(handle));
    }
    pool.clearRetainingCapacity();

    var seen = [_]bool{false} ** old.len;
    for (0..old.len) |i| {
        const handle = try pool.create(@intCast(i));
        try testing.expect(handle.index < seen.len);
        try testing.expect(!seen[handle.index]);
        seen[handle.index] = true;
    }
    for (old) |handle| try testing.expect(pool.get(handle) == null);
    try testing.expectEqual(@as(u32, old.len), pool.liveCount());
    try testing.expectEqual(@as(u32, old.len), pool.slotCount());
}

test "randomized operations agree with a simple generation model" {
    const P = PoolWithOptions(u32, .{ .chunk_len = 7, .generation_bits = 8 });
    const Model = struct { generation: P.Generation, value: u32, live: bool };
    var pool = P.init(testing.allocator);
    defer pool.deinit();
    var model: std.ArrayList(Model) = .empty;
    defer model.deinit(testing.allocator);
    var history: std.ArrayList(P.Handle) = .empty;
    defer history.deinit(testing.allocator);
    var prng = std.Random.DefaultPrng.init(0x504f4f4c53494445);
    const random = prng.random();

    // Force the independent model through retirement before random traffic.
    // With u8 generations, the 128th ending wraps the first slot to zero.
    var churn = try pool.create(0xffff_0000);
    try history.append(testing.allocator, churn);
    try model.append(testing.allocator, .{
        .generation = churn.generation,
        .value = 0xffff_0000,
        .live = true,
    });
    for (0..128) |iteration| {
        const expected_value = model.items[churn.index].value;
        try testing.expectEqual(@as(?u32, expected_value), pool.take(churn));
        model.items[churn.index].live = false;
        const value: u32 = 0xffff_0000 + @as(u32, @intCast(iteration));
        churn = try pool.create(value);
        try history.append(testing.allocator, churn);
        while (model.items.len <= churn.index) {
            try model.append(testing.allocator, .{ .generation = 0, .value = 0, .live = false });
        }
        model.items[churn.index] = .{
            .generation = churn.generation,
            .value = value,
            .live = true,
        };
    }
    try testing.expect(pool.retiredCount() > 0);

    for (0..20_000) |step| {
        const should_create = history.items.len == 0 or random.uintLessThan(u8, 100) < 45;
        if (should_create) {
            const value: u32 = @intCast(step);
            const handle = try pool.create(value);
            try history.append(testing.allocator, handle);
            while (model.items.len <= handle.index) {
                try model.append(testing.allocator, .{ .generation = 0, .value = 0, .live = false });
            }
            model.items[handle.index] = .{ .generation = handle.generation, .value = value, .live = true };
        } else {
            const handle = history.items[random.uintLessThan(usize, history.items.len)];
            const expected = handle.index < model.items.len and
                model.items[handle.index].live and
                model.items[handle.index].generation == handle.generation;
            switch (random.uintLessThan(u8, 3)) {
                0 => {
                    const taken = pool.take(handle);
                    if (expected) {
                        try testing.expectEqual(@as(?u32, model.items[handle.index].value), taken);
                        model.items[handle.index].live = false;
                    } else {
                        try testing.expect(taken == null);
                    }
                },
                1 => {
                    try testing.expectEqual(expected, pool.discard(handle));
                    if (expected) model.items[handle.index].live = false;
                },
                else => {
                    const actual = pool.get(handle);
                    try testing.expectEqual(expected, actual != null);
                    if (expected) try testing.expectEqual(model.items[handle.index].value, actual.?.*);
                },
            }
        }

        var expected_live: u32 = 0;
        for (model.items) |entry| expected_live += @intFromBool(entry.live);
        try testing.expectEqual(expected_live, pool.liveCount());
    }
    try testing.expect(pool.retiredCount() > 0);
}

fn allocationFailureWork(allocator: std.mem.Allocator) !void {
    const P = PoolWithOptions(u32, .{ .chunk_len = 3 });
    var pool = P.init(allocator);
    defer pool.deinit();

    // Cross several chunk boundaries, which also grows the chunk-pointer list.
    var handles: [40]P.Handle = undefined;
    for (&handles, 0..) |*handle, i| handle.* = try pool.create(@intCast(i));

    // Freed slots are reused before any further chunk is allocated.
    for (handles[0..5], 0..) |handle, i| {
        try testing.expectEqual(@as(?u32, @intCast(i)), pool.take(handle));
    }
    for (handles[5..10]) |handle| try testing.expect(pool.discard(handle));
    for (0..20) |i| _ = try pool.create(@intCast(i));
}

test "all allocation failures unwind without leaks" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        allocationFailureWork,
        .{},
    );
}
