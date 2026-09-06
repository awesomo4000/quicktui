// SPDX-License-Identifier: MPL-2.0

//! Generational handle pools with dynamically checked unique ownership.
//!
//! An object has a stable identity for its whole lifetime, while authority over
//! it rotates through ownership epochs. Only a token carrying the current epoch
//! may access, transfer, take, or discard the object.
//!
//! Like `Pool`, this type stores payloads but never deinitializes them, and it
//! is deliberately single-threaded. It allocates whole chunks as capacity
//! grows; access, transfer, take, discard, iteration, and clearing do not
//! allocate.
//!
//! Public guarantees assume callers use the documented methods. Zig does not
//! enforce field privacy; direct manipulation of implementation fields is
//! outside the ownership contract.

const std = @import("std");
const builtin = @import("builtin");
const ownership = @import("ownership.zig");
const pool = @import("pool.zig");

/// Compile-time storage, counter, and diagnostic configuration.
pub const OwnedOptions = struct {
    /// Slots per independently allocated chunk. Slot addresses never move.
    chunk_len: usize = 512,
    /// Object-generation width. Same meaning as `Pool.Options.generation_bits`.
    generation_bits: u16 = 32,
    /// Ownership-epoch width. Exhaustion fails rather than wrapping.
    ownership_bits: u16 = 64,
    /// Records create, transfer, take, discard, and clear source locations.
    track_provenance: bool = builtin.mode == .Debug,
};

/// Creates an owned pool with default options and tokens branded by `T`.
pub fn OwnedPool(comptime T: type) type {
    return OwnedPoolImpl(T, T, .{});
}

/// Creates an owned pool with custom storage and counter options.
pub fn OwnedPoolWithOptions(comptime T: type, comptime options: OwnedOptions) type {
    return OwnedPoolImpl(T, T, options);
}

/// Creates an owned pool whose handles are branded with `Tag`. Use distinct
/// tags when a program has multiple owned pools of the same value type.
pub fn TaggedOwnedPool(comptime T: type, comptime Tag: type) type {
    return OwnedPoolImpl(T, Tag, .{});
}

/// Creates a tagged owned pool with custom options.
pub fn TaggedOwnedPoolWithOptions(
    comptime T: type,
    comptime Tag: type,
    comptime options: OwnedOptions,
) type {
    return OwnedPoolImpl(T, Tag, options);
}

fn OwnedPoolImpl(comptime T: type, comptime Tag: type, comptime options: OwnedOptions) type {
    comptime {
        if (options.chunk_len == 0) @compileError("poolside chunk_len must be greater than zero");
        if (options.generation_bits < 2 or options.generation_bits > 64) {
            @compileError("poolside generation_bits must be between 2 and 64");
        }
        if (options.ownership_bits < 2 or options.ownership_bits > 64) {
            @compileError("poolside ownership_bits must be between 2 and 64");
        }
    }

    const EpochType = std.meta.Int(.unsigned, options.ownership_bits);

    return struct {
        const Self = @This();
        const OwnerState = ownership.OwnershipState(EpochType);
        const OwnershipProvenance = if (options.track_provenance) ?std.builtin.SourceLocation else void;

        /// What the inner pool stores. No documented method returns it.
        /// Keeping `T` inline preserves address stability: a transfer only
        /// touches the adjacent ownership metadata.
        const StoredEntry = struct {
            ownership: OwnerState,
            ownership_issued_at: OwnershipProvenance,
            value: T,
        };

        /// Undocumented implementation type. Reaching through `Self.inner`
        /// deliberately bypasses the ownership contract.
        const Inner = pool.TaggedPoolWithOptions(StoredEntry, Tag, .{
            .chunk_len = options.chunk_len,
            .generation_bits = options.generation_bits,
            .track_provenance = options.track_provenance,
        });

        /// The stored payload type.
        pub const Value = T;
        /// The type this pool's handles and tokens are branded with.
        pub const PoolTag = Tag;
        /// The object-generation integer, sized by `generation_bits`.
        pub const Generation = Inner.Generation;
        /// The ownership-epoch integer, sized by `ownership_bits`.
        pub const OwnershipEpoch = EpochType;
        /// The options this pool type was instantiated with.
        pub const config = options;

        /// A non-owning identity. It grants no payload access.
        pub const ObjectHandle = Inner.Handle;

        /// The authority token: an object identity plus a claimed epoch.
        pub const OwnedHandle = ownership.OwnedHandle(
            ObjectHandle,
            OwnershipEpoch,
            PoolTag,
        );

        /// Same capacity-growth failures as `Pool.create`.
        pub const CreateError = Inner.CreateError;
        /// Transfer failures distinguish object lifetime, authority, and epoch
        /// exhaustion. Every failure leaves the pool and source token intact.
        pub const TransferError = error{
            StaleObject,
            StaleOwnership,
            OwnershipExhausted,
        };

        /// Undocumented implementation state. Zig field visibility is
        /// conventional; direct access is outside the supported API.
        inner: Inner,
        /// One effective guard for the wrapper and its inner pool.
        pointer_lock: std.debug.SafetyLock = .{},

        /// Initializes an empty owned pool without allocating.
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .inner = Inner.init(allocator) };
        }

        /// Releases the pool's own storage. Live payloads are discarded without
        /// being read, so callers owning resources must clean them first.
        pub fn deinit(self: *Self) void {
            self.pointer_lock.assertUnlocked();
            self.inner.deinit();
            self.* = undefined;
        }

        /// Rejects pointer-invalidating and authority-revoking operations until
        /// `unlockPointers`. Bracket the lifetime of a pointer returned by an
        /// accessor or iterator to get a Debug and ReleaseSafe diagnostic
        /// instead of silent use-after-invalidation.
        ///
        /// `create` stays allowed because a new chunk never moves an existing
        /// slot. The guard protects addresses and authority, not iterator
        /// completeness, which remains a documented caller rule.
        pub fn lockPointers(self: *Self) void {
            self.pointer_lock.lock();
        }

        /// Ends the pointer guard started by `lockPointers`.
        pub fn unlockPointers(self: *Self) void {
            self.pointer_lock.unlock();
        }

        /// Stores `value` and returns the token for epoch one. Reusing a slot
        /// does not allocate. On error the pool has not accepted `value`.
        pub fn create(self: *Self, value: T) CreateError!OwnedHandle {
            return self.createImpl(value, null);
        }

        /// Like `create`, recording `source` as both the creation and initial
        /// ownership-issuance site when provenance is enabled.
        pub fn createAt(
            self: *Self,
            value: T,
            source: std.builtin.SourceLocation,
        ) CreateError!OwnedHandle {
            return self.createImpl(value, source);
        }

        fn createImpl(
            self: *Self,
            value: T,
            source: ?std.builtin.SourceLocation,
        ) CreateError!OwnedHandle {
            const state = OwnerState.init();
            const entry = StoredEntry{
                .ownership = state,
                .ownership_issued_at = if (options.track_provenance) source else {},
                .value = value,
            };
            const object = if (source) |site|
                try self.inner.createAt(entry, site)
            else
                try self.inner.create(entry);
            return OwnedHandle.init(object, state.current());
        }

        /// Tests object identity and liveness only.
        pub fn contains(self: *const Self, object: ObjectHandle) bool {
            return self.inner.contains(object);
        }

        /// Tests object identity, liveness, and the ownership epoch.
        pub fn owns(self: *const Self, owned: OwnedHandle) bool {
            return self.ownedEntryConst(owned) != null;
        }

        /// Returns a stable pointer only when the object and ownership epoch
        /// are current. The pointer remains subject to the ownership lifetime.
        pub fn get(self: *Self, owned: OwnedHandle) ?*T {
            const entry = self.ownedEntry(owned) orelse return null;
            return &entry.value;
        }

        /// Const form of `get`.
        pub fn getConst(self: *const Self, owned: OwnedHandle) ?*const T {
            const entry = self.ownedEntryConst(owned) orelse return null;
            return &entry.value;
        }

        /// Returns the current value pointer or panics with separate stale
        /// object and stale ownership diagnostics.
        pub fn expect(self: *Self, owned: OwnedHandle) *T {
            return self.get(owned) orelse self.staleAccess(owned);
        }

        /// Const form of `expect`.
        pub fn expectConst(self: *const Self, owned: OwnedHandle) *const T {
            return self.getConst(owned) orelse self.staleAccess(owned);
        }

        /// Rotates authority over a live object to a new epoch and returns the
        /// replacement token. The payload, its address, the object identity,
        /// and every pool count are unchanged; only the epoch moves.
        ///
        /// `source` is a pointer because the operation has two outputs: it
        /// clears that variable's claim and returns the replacement. Other
        /// copies of the old token are not reachable, but they go stale
        /// because the authoritative epoch advanced.
        ///
        /// On any error the entry and `source.*` are left exactly as they were.
        /// Transfer performs no allocation.
        pub fn transfer(self: *Self, source: *OwnedHandle) TransferError!OwnedHandle {
            return self.transferImpl(source, null);
        }

        /// Like `transfer`, recording `location` as the new ownership-issuance
        /// site when provenance is enabled.
        pub fn transferAt(
            self: *Self,
            source: *OwnedHandle,
            location: std.builtin.SourceLocation,
        ) TransferError!OwnedHandle {
            return self.transferImpl(source, location);
        }

        fn transferImpl(
            self: *Self,
            source: *OwnedHandle,
            location: ?std.builtin.SourceLocation,
        ) TransferError!OwnedHandle {
            self.pointer_lock.assertUnlocked();

            const object = source.object();
            const entry = self.inner.get(object) orelse return error.StaleObject;

            // Epoch advancement stays inside OwnershipState, which validates
            // the claim, refuses to wrap, and leaves itself unchanged on error.
            const next_epoch = try entry.ownership.transfer(source.ownership_epoch);

            if (options.track_provenance) entry.ownership_issued_at = location;
            const replacement = OwnedHandle.init(object, next_epoch);
            source.clear();
            return replacement;
        }

        /// Transfers the stored payload to the current owner and ends the
        /// object's lifetime. A stale, cleared, forged, or wrong-epoch token
        /// returns null and changes nothing.
        ///
        /// The returned value belongs to the caller. No pool operation calls a
        /// method on `T`.
        pub fn take(self: *Self, owned: OwnedHandle) ?T {
            return self.takeImpl(owned, null);
        }

        /// Like `take`, recording `source` as the end-of-lifetime site when
        /// provenance is enabled.
        pub fn takeAt(
            self: *Self,
            owned: OwnedHandle,
            source: std.builtin.SourceLocation,
        ) ?T {
            return self.takeImpl(owned, source);
        }

        fn takeImpl(self: *Self, owned: OwnedHandle, source: ?std.builtin.SourceLocation) ?T {
            self.pointer_lock.assertUnlocked();
            const entry = self.ownedEntry(owned) orelse return null;

            // Copy the payload once, then end the inner lifetime without
            // materializing the stored entry. Inner discard performs the same
            // provenance, generation, retirement, and count transitions as
            // inner take, and never reads the slot.
            const taken = entry.value;
            const ended = if (source) |site|
                self.inner.discardAt(owned.object(), site)
            else
                self.inner.discard(owned.object());
            std.debug.assert(ended);
            return taken;
        }

        /// Ends an object's lifetime without reading its payload. Use it for
        /// plain values, or after cleaning a value in place through `get`.
        pub fn discard(self: *Self, owned: OwnedHandle) bool {
            return self.discardImpl(owned, null);
        }

        /// Like `discard`, recording `source` as the end-of-lifetime site when
        /// provenance is enabled.
        pub fn discardAt(
            self: *Self,
            owned: OwnedHandle,
            source: std.builtin.SourceLocation,
        ) bool {
            return self.discardImpl(owned, source);
        }

        fn discardImpl(self: *Self, owned: OwnedHandle, source: ?std.builtin.SourceLocation) bool {
            self.pointer_lock.assertUnlocked();
            if (self.ownedEntry(owned) == null) return false;
            return if (source) |site|
                self.inner.discardAt(owned.object(), site)
            else
                self.inner.discard(owned.object());
        }

        /// Invalidates every live object and discards the stored payload bits
        /// without reading them, retaining allocated chunks.
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
            if (source) |site| {
                self.inner.clearRetainingCapacityAt(site);
            } else {
                self.inner.clearRetainingCapacity();
            }
        }

        /// One live object: a token for its current epoch and a pointer to
        /// its value.
        pub const Entry = struct {
            handle: OwnedHandle,
            value: *T,
        };

        /// Const form of `Entry`.
        pub const ConstEntry = struct {
            handle: OwnedHandle,
            value: *const T,
        };

        /// `next` returns only the documented entry shape. The stored inner
        /// iterator is implementation state; direct access bypasses the
        /// ownership contract.
        pub const Iterator = struct {
            inner: Inner.Iterator,

            /// Returns the next live entry, or null at the end.
            pub fn next(iter: *Iterator) ?Entry {
                const entry = iter.inner.next() orelse return null;
                return .{
                    .handle = OwnedHandle.init(entry.handle, entry.value.ownership.current()),
                    .value = &entry.value.value,
                };
            }
        };

        /// Const form of `Iterator`.
        pub const ConstIterator = struct {
            inner: Inner.ConstIterator,

            /// Returns the next live entry, or null at the end.
            pub fn next(iter: *ConstIterator) ?ConstEntry {
                const entry = iter.inner.next() orelse return null;
                return .{
                    .handle = OwnedHandle.init(entry.handle, entry.value.ownership.current()),
                    .value = &entry.value.value,
                };
            }
        };

        /// Yields every live object with a token carrying its current epoch,
        /// which is another copy of that object's authority. Administrative
        /// enumeration by the holder of the pool is not an isolation boundary.
        ///
        /// Do not create, transfer, take, discard, or clear while an iterator
        /// is active. Create keeps existing addresses valid, but an iterator
        /// continued across it has unspecified completeness and order.
        pub fn iterator(self: *Self) Iterator {
            return .{ .inner = self.inner.iterator() };
        }

        /// Const form of `iterator`.
        pub fn constIterator(self: *const Self) ConstIterator {
            return .{ .inner = self.inner.constIterator() };
        }

        /// Slot diagnostics plus the current ownership issuance when live.
        pub const ProvenanceInfo = struct {
            current_generation: Generation,
            live: bool,
            born_at: ?std.builtin.SourceLocation,
            ended_at: ?std.builtin.SourceLocation,

            /// Null when the slot is not live.
            current_ownership_epoch: ?OwnershipEpoch,

            /// Creation site for epoch one; most recent transfer site after.
            ownership_issued_at: ?std.builtin.SourceLocation,
        };

        /// Returns diagnostics for the object's slot when provenance is
        /// enabled. Metadata is slot-oriented: for a stale object handle whose
        /// index is in range, the result describes the slot's current occupant
        /// and the most recently recorded end of a lifetime.
        pub fn provenance(self: *const Self, object: ObjectHandle) ?ProvenanceInfo {
            const inner_info = self.inner.provenance(object) orelse return null;
            var info = ProvenanceInfo{
                .current_generation = inner_info.current_generation,
                .live = inner_info.live,
                .born_at = inner_info.born_at,
                .ended_at = inner_info.ended_at,
                .current_ownership_epoch = null,
                .ownership_issued_at = null,
            };

            // Take, discard, and clear leave the stored entry undefined, so the
            // ownership fields are read only through a handle for the slot's
            // current occupant, which resolves only while that occupant lives.
            const current_object = ObjectHandle{
                .index = object.index,
                .generation = inner_info.current_generation,
            };
            if (self.inner.getConst(current_object)) |entry| {
                info.current_ownership_epoch = entry.ownership.current();
                info.ownership_issued_at = if (options.track_provenance)
                    entry.ownership_issued_at
                else
                    null;
            }
            return info;
        }

        /// Number of currently live objects.
        pub fn liveCount(self: *const Self) u32 {
            return self.inner.liveCount();
        }

        /// Number of slots ever introduced, including free and retired slots.
        pub fn slotCount(self: *const Self) u32 {
            return self.inner.slotCount();
        }

        /// Number of slots permanently retired after generation exhaustion.
        pub fn retiredCount(self: *const Self) u32 {
            return self.inner.retiredCount();
        }

        /// Resolves the object first, then the ownership epoch. Ownership is
        /// never compared before the object generation is known to be live and
        /// current.
        fn ownedEntry(self: *Self, owned: OwnedHandle) ?*StoredEntry {
            const entry = self.inner.get(owned.object()) orelse return null;
            if (!entry.ownership.matches(owned.ownership_epoch)) return null;
            return entry;
        }

        fn ownedEntryConst(self: *const Self, owned: OwnedHandle) ?*const StoredEntry {
            const entry = self.inner.getConst(owned.object()) orelse return null;
            if (!entry.ownership.matches(owned.ownership_epoch)) return null;
            return entry;
        }

        /// Distinguishes a dead object from a live object whose authority has
        /// moved on, because the two failures have different causes.
        fn staleAccess(self: *const Self, owned: OwnedHandle) noreturn {
            const object = owned.object();
            if (self.inner.getConst(object)) |entry| {
                if (options.track_provenance) {
                    if (entry.ownership_issued_at) |site| {
                        std.debug.panic(
                            "stale poolside ownership epoch {d} for object {d}/{d}; " ++
                                "current epoch {d} was issued at {s}:{d}:{d} in {s}",
                            .{
                                owned.ownership_epoch,
                                object.index,
                                object.generation,
                                entry.ownership.current(),
                                site.file,
                                site.line,
                                site.column,
                                site.fn_name,
                            },
                        );
                    }
                }
                std.debug.panic(
                    "stale poolside ownership epoch {d} for object {d}/{d}; current epoch is {d}",
                    .{ owned.ownership_epoch, object.index, object.generation, entry.ownership.current() },
                );
            }
            if (options.track_provenance) {
                if (self.inner.provenance(object)) |info| {
                    if (info.ended_at) |site| {
                        std.debug.panic(
                            "stale poolside object handle {d}/{d}; " ++
                                "object lifetime ended at {s}:{d}:{d} in {s}",
                            .{
                                object.index,
                                object.generation,
                                site.file,
                                site.line,
                                site.column,
                                site.fn_name,
                            },
                        );
                    }
                }
            }
            std.debug.panic(
                "stale poolside object handle {d}/{d}",
                .{ object.index, object.generation },
            );
        }
    };
}

const testing = std.testing;

/// Payload that owns a resource and counts explicit cleanups. The pool must
/// never call `deinit`, so every counted cleanup is one a test made.
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

test "create issues epoch one and the value resolves through the token" {
    const P = OwnedPool(u64);
    var owned_pool = P.init(testing.allocator);
    defer owned_pool.deinit();

    const token = try owned_pool.create(10);
    try testing.expectEqual(@as(P.OwnershipEpoch, 1), token.ownership_epoch);
    try testing.expect(owned_pool.owns(token));
    try testing.expectEqual(@as(u64, 10), owned_pool.getConst(token).?.*);
    try testing.expectEqual(@as(u32, 1), owned_pool.liveCount());

    owned_pool.expect(token).* = 20;
    try testing.expectEqual(@as(u64, 20), owned_pool.expectConst(token).*);

    // The object identity is live but grants no payload access of its own.
    const object = token.object();
    try testing.expect(owned_pool.contains(object));
    try testing.expect(!@hasDecl(P, "getObject"));
}

test "a wrong epoch is rejected everywhere the object is not" {
    const P = OwnedPool(u32);
    var owned_pool = P.init(testing.allocator);
    defer owned_pool.deinit();

    const token = try owned_pool.create(1);
    const wrong_epoch = P.OwnedHandle.init(token.object(), 2);
    var cleared = token;
    cleared.clear();

    // The object is live, so only the ownership check can reject these.
    try testing.expect(owned_pool.contains(token.object()));
    for ([_]P.OwnedHandle{ wrong_epoch, cleared }) |rejected| {
        try testing.expect(!owned_pool.owns(rejected));
        try testing.expect(owned_pool.get(rejected) == null);
        try testing.expect(owned_pool.getConst(rejected) == null);
        try testing.expect(owned_pool.take(rejected) == null);
        try testing.expect(!owned_pool.discard(rejected));
    }
    try testing.expectEqual(@as(u32, 1), owned_pool.liveCount());
    try testing.expect(owned_pool.owns(token));
}

test "forged and out-of-range tokens fail safely" {
    const P = OwnedPoolWithOptions(u32, .{ .generation_bits = 8 });
    var owned_pool = P.init(testing.allocator);
    defer owned_pool.deinit();

    const token = try owned_pool.create(1);
    const object = token.object();

    const even_generation = P.OwnedHandle.init(
        .{ .index = object.index, .generation = object.generation +% 1 },
        token.ownership_epoch,
    );
    const out_of_range = P.OwnedHandle.init(.{ .index = 1000, .generation = 1 }, 1);
    const none_object = P.OwnedHandle.init(P.ObjectHandle.none, 1);
    const zero_epoch = P.OwnedHandle.init(object, 0);

    for ([_]P.OwnedHandle{ even_generation, out_of_range, none_object, zero_epoch }) |forged| {
        try testing.expect(!owned_pool.owns(forged));
        try testing.expect(owned_pool.get(forged) == null);
        try testing.expect(owned_pool.take(forged) == null);
        try testing.expect(!owned_pool.discard(forged));
    }
    try testing.expect(!owned_pool.contains(P.ObjectHandle.none));
    try testing.expectEqual(@as(u32, 1), owned_pool.liveCount());
}

test "take returns the payload once and invalidates every token copy" {
    const P = OwnedPool(u64);
    var owned_pool = P.init(testing.allocator);
    defer owned_pool.deinit();

    const token = try owned_pool.create(42);
    const copy = token;
    const object = token.object();

    try testing.expectEqual(@as(?u64, 42), owned_pool.take(token));
    try testing.expectEqual(@as(u32, 0), owned_pool.liveCount());
    try testing.expect(owned_pool.take(copy) == null);
    try testing.expect(!owned_pool.discard(copy));
    try testing.expect(!owned_pool.owns(copy));
    try testing.expect(!owned_pool.contains(object));
}

test "slot reuse changes object generation and restarts the epoch at one" {
    const P = OwnedPool(u32);
    var owned_pool = P.init(testing.allocator);
    defer owned_pool.deinit();

    const first = try owned_pool.create(1);
    try testing.expect(owned_pool.discard(first));

    const second = try owned_pool.create(2);
    try testing.expectEqual(first.object().index, second.object().index);
    try testing.expect(first.object().generation != second.object().generation);
    try testing.expectEqual(@as(P.OwnershipEpoch, 1), second.ownership_epoch);

    // Matching epochs cannot revive the old token: the object generation moved.
    try testing.expectEqual(first.ownership_epoch, second.ownership_epoch);
    try testing.expect(!owned_pool.owns(first));
    try testing.expect(owned_pool.owns(second));
}

test "payload addresses stay stable as the chunk table grows" {
    const P = OwnedPoolWithOptions(u64, .{ .chunk_len = 2 });
    var owned_pool = P.init(testing.allocator);
    defer owned_pool.deinit();

    const token = try owned_pool.create(1234);
    const pointer = owned_pool.get(token).?;
    for (0..100) |i| _ = try owned_pool.create(@intCast(i));

    try testing.expectEqual(@intFromPtr(pointer), @intFromPtr(owned_pool.get(token).?));
    try testing.expectEqual(@as(u64, 1234), pointer.*);
}

test "take transfers a resource-owning payload exactly once" {
    var cleanups: usize = 0;
    var owned_pool = OwnedPool(CountedResource).init(testing.allocator);
    defer owned_pool.deinit();

    const token = try owned_pool.create(try CountedResource.init(testing.allocator, &cleanups));
    var taken = owned_pool.take(token).?;
    taken.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), cleanups);

    // A stale take cannot produce a second value to clean up.
    try testing.expect(owned_pool.take(token) == null);
    try testing.expectEqual(@as(usize, 1), cleanups);
}

test "discard succeeds after an in-place cleanup leaves the value undefined" {
    var cleanups: usize = 0;
    var owned_pool = OwnedPool(CountedResource).init(testing.allocator);
    defer owned_pool.deinit();

    const token = try owned_pool.create(try CountedResource.init(testing.allocator, &cleanups));
    owned_pool.get(token).?.deinit(testing.allocator);
    try testing.expect(owned_pool.discard(token));
    try testing.expectEqual(@as(usize, 1), cleanups);
    try testing.expect(!owned_pool.discard(token));
}

test "the pool calls no payload method during take, discard, clear, or deinit" {
    var cleanups: usize = 0;
    var owned_pool = OwnedPool(CountedResource).init(testing.allocator);

    const taken_token = try owned_pool.create(try CountedResource.init(testing.allocator, &cleanups));
    const discarded_token = try owned_pool.create(try CountedResource.init(testing.allocator, &cleanups));

    var taken = owned_pool.take(taken_token).?;
    try testing.expectEqual(@as(usize, 0), cleanups);
    taken.deinit(testing.allocator);

    owned_pool.get(discarded_token).?.deinit(testing.allocator);
    try testing.expect(owned_pool.discard(discarded_token));
    try testing.expectEqual(@as(usize, 2), cleanups);

    const cleared_token = try owned_pool.create(try CountedResource.init(testing.allocator, &cleanups));
    owned_pool.get(cleared_token).?.deinit(testing.allocator);
    owned_pool.clearRetainingCapacity();
    try testing.expectEqual(@as(usize, 3), cleanups);
    try testing.expectEqual(@as(u32, 0), owned_pool.liveCount());

    const remaining = try owned_pool.create(try CountedResource.init(testing.allocator, &cleanups));
    owned_pool.get(remaining).?.deinit(testing.allocator);
    owned_pool.deinit();
    try testing.expectEqual(@as(usize, 4), cleanups);
}

test "failed creation leaves payload ownership with the caller" {
    var cleanups: usize = 0;
    var failing = std.testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    var owned_pool = OwnedPool(CountedResource).init(failing.allocator());
    defer owned_pool.deinit();

    var value = try CountedResource.init(testing.allocator, &cleanups);
    try testing.expectError(error.OutOfMemory, owned_pool.create(value));
    try testing.expectEqual(@as(usize, 0), cleanups);
    try testing.expectEqual(@as(u32, 0), owned_pool.liveCount());

    value.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), cleanups);
}

test "payload declarations named deinit are never inspected" {
    const OddSignature = struct {
        value: u32,

        pub fn deinit(self: @This(), first: u32, second: u32) u64 {
            return self.value + first + second;
        }
    };
    var odd = OwnedPool(OddSignature).init(testing.allocator);
    defer odd.deinit();

    const token = try odd.create(.{ .value = 1 });
    try testing.expectEqual(@as(u32, 1), odd.take(token).?.value);
}

test "clear invalidates every token and reuses the slots" {
    const P = OwnedPoolWithOptions(u16, .{ .chunk_len = 3 });
    var owned_pool = P.init(testing.allocator);
    defer owned_pool.deinit();

    var old: [10]P.OwnedHandle = undefined;
    for (&old, 0..) |*token, i| token.* = try owned_pool.create(@intCast(i));
    owned_pool.clearRetainingCapacity();

    try testing.expectEqual(@as(u32, 0), owned_pool.liveCount());
    for (old) |token| {
        try testing.expect(!owned_pool.owns(token));
        try testing.expect(!owned_pool.contains(token.object()));
    }

    var seen = [_]bool{false} ** old.len;
    for (0..old.len) |i| {
        const token = try owned_pool.create(@intCast(i));
        try testing.expect(!seen[token.object().index]);
        seen[token.object().index] = true;
    }
    try testing.expectEqual(@as(u32, old.len), owned_pool.slotCount());
}

test "transfer preserves object identity and advances the epoch" {
    const P = OwnedPool(u64);
    var owned_pool = P.init(testing.allocator);
    defer owned_pool.deinit();

    var producer = try owned_pool.create(7);
    const object = producer.object();
    const address = @intFromPtr(owned_pool.get(producer).?);
    const live_before = owned_pool.liveCount();
    const slots_before = owned_pool.slotCount();
    const retired_before = owned_pool.retiredCount();

    const consumer = try owned_pool.transfer(&producer);
    try testing.expectEqual(@as(P.OwnershipEpoch, 2), consumer.ownership_epoch);
    try testing.expect(std.meta.eql(object, consumer.object()));

    // The source variable keeps its identity but loses its claim.
    try testing.expect(producer.isCleared());
    try testing.expect(std.meta.eql(object, producer.object()));

    // Nothing about the object or the pool moved.
    try testing.expectEqual(address, @intFromPtr(owned_pool.get(consumer).?));
    try testing.expectEqual(@as(u64, 7), owned_pool.getConst(consumer).?.*);
    try testing.expectEqual(live_before, owned_pool.liveCount());
    try testing.expectEqual(slots_before, owned_pool.slotCount());
    try testing.expectEqual(retired_before, owned_pool.retiredCount());
    try testing.expect(owned_pool.contains(object));
}

test "a copy of the old token stops resolving after transfer" {
    const P = OwnedPool(u32);
    var owned_pool = P.init(testing.allocator);
    defer owned_pool.deinit();

    var producer = try owned_pool.create(1);
    const old_copy = producer;
    const consumer = try owned_pool.transfer(&producer);

    try testing.expect(!owned_pool.owns(old_copy));
    try testing.expect(owned_pool.get(old_copy) == null);
    try testing.expect(owned_pool.take(old_copy) == null);
    try testing.expect(!owned_pool.discard(old_copy));

    var stale = old_copy;
    try testing.expectError(error.StaleOwnership, owned_pool.transfer(&stale));

    // The rejected attempt left the stale variable and the object alone.
    try testing.expect(stale.eql(old_copy));
    try testing.expect(owned_pool.owns(consumer));
    try testing.expectEqual(@as(u32, 1), owned_pool.liveCount());
}

test "a failed transfer changes neither the source nor the stored state" {
    const P = OwnedPool(u32);
    var owned_pool = P.init(testing.allocator);
    defer owned_pool.deinit();

    const token = try owned_pool.create(1);
    var cleared = token;
    cleared.clear();
    var forged = P.OwnedHandle.init(token.object(), token.ownership_epoch + 5);

    try testing.expectError(error.StaleOwnership, owned_pool.transfer(&cleared));
    try testing.expect(cleared.isCleared());
    try testing.expectError(error.StaleOwnership, owned_pool.transfer(&forged));
    try testing.expectEqual(token.ownership_epoch + 5, forged.ownership_epoch);

    // The current token is still current after both rejections.
    try testing.expect(owned_pool.owns(token));
    var current = token;
    const next = try owned_pool.transfer(&current);
    try testing.expectEqual(@as(P.OwnershipEpoch, 2), next.ownership_epoch);
}

test "transferring a dead object reports a stale object" {
    const P = OwnedPool(u32);
    var owned_pool = P.init(testing.allocator);
    defer owned_pool.deinit();

    const token = try owned_pool.create(1);
    const copy = token;
    try testing.expectEqual(@as(?u32, 1), owned_pool.take(token));

    // Object validation runs first, so an ended lifetime outranks the epoch.
    var stale = copy;
    try testing.expectError(error.StaleObject, owned_pool.transfer(&stale));

    var forged = P.OwnedHandle.init(.{ .index = 900, .generation = 1 }, 1);
    try testing.expectError(error.StaleObject, owned_pool.transfer(&forged));

    var none_object = P.OwnedHandle.init(P.ObjectHandle.none, 1);
    try testing.expectError(error.StaleObject, owned_pool.transfer(&none_object));
}

test "many transfers keep the payload address and allow one take" {
    var cleanups: usize = 0;
    var owned_pool = OwnedPool(CountedResource).init(testing.allocator);
    defer owned_pool.deinit();

    var token = try owned_pool.create(try CountedResource.init(testing.allocator, &cleanups));
    const address = @intFromPtr(owned_pool.get(token).?);
    for (0..64) |_| token = try owned_pool.transfer(&token);
    try testing.expectEqual(address, @intFromPtr(owned_pool.get(token).?));

    var taken = owned_pool.take(token).?;
    taken.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), cleanups);
    try testing.expectEqual(@as(u32, 0), owned_pool.liveCount());
}

test "an exhausted epoch keeps the current token usable" {
    const P = OwnedPoolWithOptions(u32, .{ .chunk_len = 1, .ownership_bits = 2 });
    var owned_pool = P.init(testing.allocator);
    defer owned_pool.deinit();

    // Keep a copy of each token before transfer clears the source variable,
    // so the checks below run against real historical epochs rather than
    // against cleared ones.
    var first = try owned_pool.create(1);
    const epoch_one = first;
    var second = try owned_pool.transfer(&first);
    const epoch_two = second;
    try testing.expectEqual(@as(P.OwnershipEpoch, 2), second.ownership_epoch);
    var third = try owned_pool.transfer(&second);
    const epoch_three = third;
    try testing.expectEqual(@as(P.OwnershipEpoch, 3), third.ownership_epoch);

    // The counter stops instead of wrapping to zero or one.
    try testing.expectError(error.OwnershipExhausted, owned_pool.transfer(&third));
    try testing.expect(!third.isCleared());
    try testing.expectEqual(@as(P.OwnershipEpoch, 3), third.ownership_epoch);

    // Exhaustion revokes nothing: the object is still readable and takeable.
    try testing.expect(owned_pool.owns(third));
    try testing.expectEqual(@as(u32, 1), owned_pool.expect(third).*);
    try testing.expectEqual(@as(u32, 0), owned_pool.retiredCount());
    try testing.expectEqual(@as(?u32, 1), owned_pool.take(third));

    // The reused slot starts a fresh ownership sequence that no old token
    // can enter, because the object generation advanced.
    const reused = try owned_pool.create(2);
    try testing.expectEqual(epoch_one.object().index, reused.object().index);
    try testing.expectEqual(@as(P.OwnershipEpoch, 1), reused.ownership_epoch);

    // Every historical token is stale, including the one whose epoch equals
    // the new occupant's, and including the cleared source variables.
    const history = [_]P.OwnedHandle{ epoch_one, epoch_two, epoch_three, first, second, third };
    for (history, 0..) |old, index| {
        if (index < 3) try testing.expectEqual(@as(P.OwnershipEpoch, @intCast(index + 1)), old.ownership_epoch);
        try testing.expect(!owned_pool.owns(old));
        try testing.expect(owned_pool.get(old) == null);
        try testing.expect(owned_pool.take(old) == null);
        try testing.expect(!owned_pool.discard(old));
    }
    try testing.expect(epoch_one.ownership_epoch == reused.ownership_epoch);
    try testing.expect(owned_pool.owns(reused));
}

test "exhaustion can also be ended with discard" {
    const P = OwnedPoolWithOptions(u32, .{ .ownership_bits = 2 });
    var owned_pool = P.init(testing.allocator);
    defer owned_pool.deinit();

    var token = try owned_pool.create(1);
    token = try owned_pool.transfer(&token);
    token = try owned_pool.transfer(&token);
    try testing.expectError(error.OwnershipExhausted, owned_pool.transfer(&token));
    try testing.expect(owned_pool.discard(token));
    try testing.expectEqual(@as(u32, 0), owned_pool.liveCount());
}

test "transfer performs no allocation" {
    var failing = std.testing.FailingAllocator.init(testing.allocator, .{});
    const P = OwnedPoolWithOptions(u32, .{ .chunk_len = 4 });
    var owned_pool = P.init(failing.allocator());
    defer owned_pool.deinit();

    var token = try owned_pool.create(1);
    const allocations = failing.allocations;
    for (0..16) |_| token = try owned_pool.transfer(&token);
    try testing.expectEqual(allocations, failing.allocations);
}

test "provenance records the site that issued the current epoch" {
    const P = OwnedPoolWithOptions(u8, .{ .track_provenance = true });
    var owned_pool = P.init(testing.allocator);
    defer owned_pool.deinit();

    const born = @src();
    var token = try owned_pool.createAt(1, born);
    const object = token.object();

    const created = owned_pool.provenance(object).?;
    try testing.expect(created.live);
    try testing.expectEqual(born.line, created.born_at.?.line);
    try testing.expectEqual(@as(?P.OwnershipEpoch, 1), created.current_ownership_epoch);
    try testing.expectEqual(born.line, created.ownership_issued_at.?.line);
    try testing.expect(created.ended_at == null);

    const handoff = @src();
    token = try owned_pool.transferAt(&token, handoff);
    const transferred = owned_pool.provenance(object).?;
    try testing.expectEqual(@as(?P.OwnershipEpoch, 2), transferred.current_ownership_epoch);
    try testing.expectEqual(handoff.line, transferred.ownership_issued_at.?.line);

    // The object identity is untouched by the handoff.
    try testing.expectEqual(born.line, transferred.born_at.?.line);
    try testing.expectEqual(created.current_generation, transferred.current_generation);

    // A transfer without a site clears the issuing location.
    token = try owned_pool.transfer(&token);
    const untracked_transfer = owned_pool.provenance(object).?;
    try testing.expectEqual(@as(?P.OwnershipEpoch, 3), untracked_transfer.current_ownership_epoch);
    try testing.expect(untracked_transfer.ownership_issued_at == null);
}

test "a dead slot reports no ownership without reading the stored entry" {
    const P = OwnedPoolWithOptions(u8, .{ .track_provenance = true });
    var owned_pool = P.init(testing.allocator);
    defer owned_pool.deinit();

    const taken_token = try owned_pool.createAt(1, @src());
    const taken_object = taken_token.object();
    const taken_at = @src();
    try testing.expectEqual(@as(?u8, 1), owned_pool.takeAt(taken_token, taken_at));

    const after_take = owned_pool.provenance(taken_object).?;
    try testing.expect(!after_take.live);
    try testing.expectEqual(taken_at.line, after_take.ended_at.?.line);
    try testing.expect(after_take.current_ownership_epoch == null);
    try testing.expect(after_take.ownership_issued_at == null);

    const discard_token = try owned_pool.createAt(2, @src());
    const discard_object = discard_token.object();
    const discarded_at = @src();
    try testing.expect(owned_pool.discardAt(discard_token, discarded_at));
    const after_discard = owned_pool.provenance(discard_object).?;
    try testing.expect(!after_discard.live);
    try testing.expectEqual(discarded_at.line, after_discard.ended_at.?.line);
    try testing.expect(after_discard.current_ownership_epoch == null);

    const cleared_token = try owned_pool.createAt(3, @src());
    const clear_source = @src();
    owned_pool.clearRetainingCapacityAt(clear_source);
    const after_clear = owned_pool.provenance(cleared_token.object()).?;
    try testing.expect(!after_clear.live);
    try testing.expectEqual(clear_source.line, after_clear.ended_at.?.line);
    try testing.expect(after_clear.ownership_issued_at == null);
}

test "a stale object handle reports the slot's new occupant" {
    const P = OwnedPoolWithOptions(u8, .{ .track_provenance = true });
    var owned_pool = P.init(testing.allocator);
    defer owned_pool.deinit();

    const first = try owned_pool.createAt(1, @src());
    const stale_object = first.object();
    try testing.expect(owned_pool.discardAt(first, @src()));

    const reborn = @src();
    var second = try owned_pool.createAt(2, reborn);
    try testing.expectEqual(stale_object.index, second.object().index);
    second = try owned_pool.transfer(&second);

    // Provenance is slot-oriented, so the stale handle describes the occupant
    // that lives there now.
    const info = owned_pool.provenance(stale_object).?;
    try testing.expect(info.live);
    try testing.expect(info.current_generation != stale_object.generation);
    try testing.expectEqual(reborn.line, info.born_at.?.line);
    try testing.expectEqual(@as(?P.OwnershipEpoch, 2), info.current_ownership_epoch);
}

test "disabled provenance returns null and stores no metadata" {
    const Tracked = OwnedPoolWithOptions(u8, .{ .track_provenance = true });
    const Untracked = OwnedPoolWithOptions(u8, .{ .track_provenance = false });

    try testing.expectEqual(@as(usize, 0), @sizeOf(Untracked.OwnershipProvenance));
    try testing.expect(@sizeOf(Tracked.OwnershipProvenance) > 0);
    try testing.expect(@sizeOf(Untracked.StoredEntry) < @sizeOf(Tracked.StoredEntry));

    var owned_pool = Untracked.init(testing.allocator);
    defer owned_pool.deinit();

    var token = try owned_pool.createAt(1, @src());
    try testing.expect(owned_pool.provenance(token.object()) == null);
    token = try owned_pool.transferAt(&token, @src());
    try testing.expect(owned_pool.provenance(token.object()) == null);
    try testing.expect(owned_pool.discardAt(token, @src()));
    try testing.expect(owned_pool.provenance(token.object()) == null);
}

test "iteration skips dead slots and emits current tokens" {
    const P = OwnedPoolWithOptions(u32, .{ .chunk_len = 2 });
    var owned_pool = P.init(testing.allocator);
    defer owned_pool.deinit();

    const kept = try owned_pool.create(1);
    var transferred = try owned_pool.create(2);
    const taken = try owned_pool.create(4);
    const discarded = try owned_pool.create(8);

    transferred = try owned_pool.transfer(&transferred);
    try testing.expectEqual(@as(?u32, 4), owned_pool.take(taken));
    try testing.expect(owned_pool.discard(discarded));

    var sum: u32 = 0;
    var count: usize = 0;
    var entries = owned_pool.iterator();
    while (entries.next()) |entry| {
        // Every yielded token is current authority for its object.
        try testing.expect(owned_pool.owns(entry.handle));
        sum += entry.value.*;
        count += 1;
    }
    try testing.expectEqual(@as(usize, 2), count);
    try testing.expectEqual(@as(u32, 3), sum);
    try testing.expect(owned_pool.owns(kept));

    const const_pool: *const P = &owned_pool;
    var const_sum: u32 = 0;
    var const_count: usize = 0;
    var const_entries = const_pool.constIterator();
    while (const_entries.next()) |entry| {
        try testing.expect(const_pool.owns(entry.handle));
        const_sum += entry.value.*;
        const_count += 1;
    }
    try testing.expectEqual(count, const_count);
    try testing.expectEqual(sum, const_sum);
}

test "an iterated token carries the epoch current at that moment" {
    const P = OwnedPool(u32);
    var owned_pool = P.init(testing.allocator);
    defer owned_pool.deinit();

    var token = try owned_pool.create(1);
    token = try owned_pool.transfer(&token);

    var collected: ?P.OwnedHandle = null;
    var entries = owned_pool.iterator();
    while (entries.next()) |entry| collected = entry.handle;

    const before_transfer = collected.?;
    try testing.expectEqual(@as(P.OwnershipEpoch, 2), before_transfer.ownership_epoch);
    try testing.expect(before_transfer.eql(token));

    // Collect first, mutate afterward: the collected token goes stale exactly
    // like any other copy of the old authority.
    var current = token;
    _ = try owned_pool.transfer(&current);
    try testing.expect(!owned_pool.owns(before_transfer));
    try testing.expect(owned_pool.get(before_transfer) == null);
}

test "cleaning live values through iteration before clear" {
    // The pattern the documentation recommends for resource-owning payloads.
    var cleanups: usize = 0;
    var owned_pool = OwnedPool(CountedResource).init(testing.allocator);
    defer owned_pool.deinit();

    for (0..4) |_| {
        _ = try owned_pool.create(try CountedResource.init(testing.allocator, &cleanups));
    }

    var entries = owned_pool.iterator();
    while (entries.next()) |entry| entry.value.deinit(testing.allocator);
    owned_pool.clearRetainingCapacity();

    try testing.expectEqual(@as(usize, 4), cleanups);
    try testing.expectEqual(@as(u32, 0), owned_pool.liveCount());
}

test "iteration yields payload pointers, not stored entries" {
    const P = OwnedPool(u32);
    comptime {
        // Pin the documented result of `next`: an entry hands out `*T` and a
        // token, nothing else. Iterator storage is an implementation detail.
        std.debug.assert(@FieldType(P.Entry, "value") == *P.Value);
        std.debug.assert(@FieldType(P.ConstEntry, "value") == *const P.Value);
        std.debug.assert(@FieldType(P.Entry, "handle") == P.OwnedHandle);
        std.debug.assert(@typeInfo(P.Entry).@"struct".fields.len == 2);
        std.debug.assert(@typeInfo(P.ConstEntry).@"struct".fields.len == 2);
    }
}

test "observation issues no authority" {
    const P = OwnedPool(u32);
    comptime {
        // Only create, transfer, and iteration return tokens. Observation
        // reports and never hands one back. Trusted code can still build a
        // claimed token out of what it reads here; the pool validates it.
        std.debug.assert(@typeInfo(@TypeOf(P.contains)).@"fn".return_type.? == bool);
        std.debug.assert(@typeInfo(@TypeOf(P.provenance)).@"fn".return_type.? == ?P.ProvenanceInfo);
        for (@typeInfo(P.ProvenanceInfo).@"struct".fields) |field| {
            std.debug.assert(field.type != P.OwnedHandle);
            std.debug.assert(field.type != ?P.OwnedHandle);
        }
    }
}

fn ownedAllocationFailureWork(allocator: std.mem.Allocator) !void {
    const P = OwnedPoolWithOptions(u32, .{ .chunk_len = 3 });
    var owned_pool = P.init(allocator);
    defer owned_pool.deinit();

    // Cross several chunk boundaries, which also grows the chunk-pointer list.
    var tokens: [40]P.OwnedHandle = undefined;
    for (&tokens, 0..) |*token, i| token.* = try owned_pool.create(@intCast(i));

    // Access, transfer, take, and discard must not allocate, so none of them
    // can fail here no matter which allocation the harness broke.
    for (tokens, 0..) |token, i| {
        try testing.expectEqual(@as(u32, @intCast(i)), owned_pool.get(token).?.*);
        try testing.expectEqual(@as(u32, @intCast(i)), owned_pool.getConst(token).?.*);
    }
    for (tokens[0..10]) |*token| token.* = try owned_pool.transfer(token);
    for (tokens[0..10]) |token| try testing.expect(owned_pool.getConst(token) != null);
    for (tokens[0..5], 0..) |token, i| {
        try testing.expectEqual(@as(?u32, @intCast(i)), owned_pool.take(token));
    }
    for (tokens[5..10]) |token| try testing.expect(owned_pool.discard(token));

    // Reuse the freed slots, then force more growth.
    for (0..20) |i| _ = try owned_pool.create(@intCast(i));
}

test "all allocation failures unwind without leaks" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        ownedAllocationFailureWork,
        .{},
    );
}

test "randomized operations agree with an independent ownership model" {
    // Narrow counters so both exhaustion paths are reachable: object
    // generations wrap after 128 endings, ownership epochs stop at 15.
    const P = OwnedPoolWithOptions(u32, .{
        .chunk_len = 5,
        .generation_bits = 8,
        .ownership_bits = 4,
    });
    const ModelState = ownership.OwnershipState(P.OwnershipEpoch);
    const Model = struct {
        generation: P.Generation,
        ownership: ModelState,
        value: u32,
        live: bool,
    };
    const max_epoch = std.math.maxInt(P.OwnershipEpoch);

    var owned_pool = P.init(testing.allocator);
    defer owned_pool.deinit();
    var model: std.ArrayList(Model) = .empty;
    defer model.deinit(testing.allocator);

    // Every token ever issued, also grouped by slot so the audit after each
    // step can revisit exactly the tokens that name the affected slot.
    var history: std.ArrayList(P.OwnedHandle) = .empty;
    defer history.deinit(testing.allocator);
    var by_slot: std.ArrayList(std.ArrayList(P.OwnedHandle)) = .empty;
    defer {
        for (by_slot.items) |*slot_tokens| slot_tokens.deinit(testing.allocator);
        by_slot.deinit(testing.allocator);
    }
    var expected_retired: u32 = 0;

    const track = struct {
        /// Records a token in both the flat history and its slot's group.
        fn remember(
            flat: *std.ArrayList(P.OwnedHandle),
            grouped: *std.ArrayList(std.ArrayList(P.OwnedHandle)),
            token: P.OwnedHandle,
        ) !void {
            try flat.append(testing.allocator, token);
            const index = token.object().index;
            while (grouped.items.len <= index) {
                try grouped.append(testing.allocator, .empty);
            }
            try grouped.items[index].append(testing.allocator, token);
        }

        fn born(
            list: *std.ArrayList(Model),
            token: P.OwnedHandle,
            value: u32,
        ) !void {
            const index = token.object().index;
            while (list.items.len <= index) {
                try list.append(testing.allocator, .{
                    .generation = 0,
                    .ownership = ModelState.init(),
                    .value = 0,
                    .live = false,
                });
            }
            list.items[index] = .{
                .generation = token.object().generation,
                .ownership = ModelState.init(),
                .value = value,
                .live = true,
            };
        }

        /// A slot is retired exactly when ending its object wraps the
        /// generation, so retirement is predicted rather than read back.
        fn ended(entry: *Model, retired: *u32) void {
            entry.live = false;
            if (entry.generation +% 1 == 0) retired.* += 1;
        }
    };

    const audit = struct {
        /// Re-resolves one historical token and checks every answer the pool
        /// gives for it against the model.
        fn token(
            checked: *P,
            list: []const Model,
            handle: P.OwnedHandle,
        ) !void {
            const object = handle.object();
            const entry = list[object.index];
            const object_live = entry.live and entry.generation == object.generation;
            const owned = object_live and entry.ownership.matches(handle.ownership_epoch);

            try testing.expectEqual(object_live, checked.contains(object));
            try testing.expectEqual(owned, checked.owns(handle));
            const actual = checked.get(handle);
            try testing.expectEqual(owned, actual != null);
            if (owned) try testing.expectEqual(entry.value, actual.?.*);
            try testing.expectEqual(owned, checked.getConst(handle) != null);
        }

        /// Checks the slot's current occupant, including that the epochs on
        /// either side of the current one are rejected.
        fn slot(checked: *P, list: []const Model, index: u32) !void {
            const entry = list[index];
            const current = P.OwnedHandle.init(
                .{ .index = index, .generation = entry.generation },
                entry.ownership.current(),
            );
            if (!entry.live) {
                try testing.expect(!checked.contains(current.object()));
                try testing.expect(!checked.owns(current));
                return;
            }

            try testing.expect(checked.contains(current.object()));
            try testing.expect(checked.owns(current));
            try testing.expectEqual(entry.value, checked.expect(current).*);
            try testing.expectEqual(entry.value, checked.getConst(current).?.*);

            const epoch = entry.ownership.current();
            if (epoch > 1) {
                const previous = P.OwnedHandle.init(current.object(), epoch - 1);
                try testing.expect(!checked.owns(previous));
            }
            if (epoch < max_epoch) {
                const unissued = P.OwnedHandle.init(current.object(), epoch + 1);
                try testing.expect(!checked.owns(unissued));
            }
            const cleared = P.OwnedHandle.init(current.object(), 0);
            try testing.expect(!checked.owns(cleared));
        }

        /// Every slot and every token ever issued, in one pass.
        fn everything(
            checked: *P,
            list: []const Model,
            flat: []const P.OwnedHandle,
            retired: u32,
        ) !void {
            var expected_live: u32 = 0;
            for (list, 0..) |entry, index| {
                expected_live += @intFromBool(entry.live);
                try slot(checked, list, @intCast(index));
            }
            for (flat) |past| try token(checked, list, past);
            try testing.expectEqual(expected_live, checked.liveCount());
            try testing.expectEqual(@as(u32, @intCast(list.len)), checked.slotCount());
            try testing.expectEqual(retired, checked.retiredCount());
        }
    };

    // Forced prefix one: drive a single slot to object-generation retirement.
    {
        var churn = try owned_pool.create(0xdead);
        try track.born(&model, churn, 0xdead);
        try track.remember(&history, &by_slot, churn);
        for (0..128) |iteration| {
            const value: u32 = @intCast(iteration);
            track.ended(&model.items[churn.object().index], &expected_retired);
            try testing.expect(owned_pool.discard(churn));
            churn = try owned_pool.create(value);
            try track.born(&model, churn, value);
            try track.remember(&history, &by_slot, churn);
        }
        try testing.expectEqual(expected_retired, owned_pool.retiredCount());
        try testing.expect(owned_pool.retiredCount() > 0);
    }

    // Forced prefix two: drive one object to ownership exhaustion.
    {
        var token = try owned_pool.create(0xbeef);
        try track.born(&model, token, 0xbeef);
        const entry = &model.items[token.object().index];
        while (entry.ownership.current() < max_epoch) {
            try track.remember(&history, &by_slot, token);
            const expected_epoch = try entry.ownership.transfer(token.ownership_epoch);
            token = try owned_pool.transfer(&token);
            try testing.expectEqual(expected_epoch, token.ownership_epoch);
        }
        var exhausted = token;
        try testing.expectError(error.OwnershipExhausted, owned_pool.transfer(&exhausted));
        try testing.expectEqual(max_epoch, token.ownership_epoch);

        // Exhaustion revokes nothing, so the object is still takeable.
        track.ended(entry, &expected_retired);
        try testing.expectEqual(@as(?u32, 0xbeef), owned_pool.take(token));
        try track.remember(&history, &by_slot, token);
    }

    try audit.everything(&owned_pool, model.items, history.items, expected_retired);

    var prng = std.Random.DefaultPrng.init(0x4f574e4544504f4c);
    const random = prng.random();

    for (0..20_000) |step| {
        // The slot this step touched, or null when the step touched all of
        // them and the sweep below covers it instead.
        var affected: ?u32 = null;

        const should_create = history.items.len == 0 or random.uintLessThan(u8, 100) < 40;
        if (should_create) {
            const value: u32 = @intCast(step);
            const token = try owned_pool.create(value);
            try track.born(&model, token, value);
            try track.remember(&history, &by_slot, token);
            affected = token.object().index;
        } else {
            const token = history.items[random.uintLessThan(usize, history.items.len)];
            const index = token.object().index;
            const entry = &model.items[index];
            const object_live = entry.live and entry.generation == token.object().generation;
            const owned = object_live and entry.ownership.matches(token.ownership_epoch);
            affected = index;

            switch (random.uintLessThan(u8, 6)) {
                0 => {
                    try testing.expectEqual(object_live, owned_pool.contains(token.object()));
                    try testing.expectEqual(owned, owned_pool.owns(token));
                },
                1 => {
                    const actual = owned_pool.get(token);
                    try testing.expectEqual(owned, actual != null);
                    if (owned) try testing.expectEqual(entry.value, actual.?.*);
                },
                2 => {
                    var source = token;
                    const result = owned_pool.transfer(&source);
                    if (!object_live) {
                        try testing.expectError(error.StaleObject, result);
                        try testing.expect(source.eql(token));
                    } else if (!entry.ownership.matches(token.ownership_epoch)) {
                        try testing.expectError(error.StaleOwnership, result);
                        try testing.expect(source.eql(token));
                    } else if (entry.ownership.current() == max_epoch) {
                        try testing.expectError(error.OwnershipExhausted, result);
                        try testing.expect(source.eql(token));
                    } else {
                        const expected_epoch = try entry.ownership.transfer(token.ownership_epoch);
                        const replacement = try result;
                        try testing.expectEqual(expected_epoch, replacement.ownership_epoch);
                        try testing.expect(std.meta.eql(token.object(), replacement.object()));
                        try testing.expect(source.isCleared());
                        try track.remember(&history, &by_slot, replacement);
                    }
                },
                3 => {
                    const taken = owned_pool.take(token);
                    try testing.expectEqual(owned, taken != null);
                    if (owned) {
                        try testing.expectEqual(entry.value, taken.?);
                        track.ended(entry, &expected_retired);
                    }
                },
                4 => {
                    try testing.expectEqual(owned, owned_pool.discard(token));
                    if (owned) track.ended(entry, &expected_retired);
                },
                else => {
                    // Rarely clear everything, which ends every live object.
                    if (random.uintLessThan(u16, 400) != 0) continue;
                    for (model.items) |*live_entry| {
                        if (live_entry.live) track.ended(live_entry, &expected_retired);
                    }
                    owned_pool.clearRetainingCapacity();
                    affected = null;
                },
            }
        }

        // Audit the slot this step touched and every token that names it, so
        // resolution, value, and epoch are checked on every step rather than
        // only when their operation happens to be selected.
        if (affected) |index| {
            try audit.slot(&owned_pool, model.items, index);
            for (by_slot.items[index].items) |past| {
                try audit.token(&owned_pool, model.items, past);
            }
        }

        var expected_live: u32 = 0;
        for (model.items) |entry| expected_live += @intFromBool(entry.live);
        try testing.expectEqual(expected_live, owned_pool.liveCount());
        try testing.expectEqual(@as(u32, @intCast(model.items.len)), owned_pool.slotCount());
        try testing.expectEqual(expected_retired, owned_pool.retiredCount());

        if (step % 1000 == 0 or affected == null) {
            try audit.everything(&owned_pool, model.items, history.items, expected_retired);
        }
    }

    try audit.everything(&owned_pool, model.items, history.items, expected_retired);
    try testing.expect(owned_pool.retiredCount() > 0);
    try testing.expect(history.items.len > 1000);
}

test "the owned handle aliases the standalone generic with branded parts" {
    const P = OwnedPool(u32);
    comptime std.debug.assert(P.OwnedHandle == ownership.OwnedHandle(
        P.ObjectHandle,
        P.OwnershipEpoch,
        P.PoolTag,
    ));
    comptime std.debug.assert(P.OwnedHandle.Object == P.ObjectHandle);
    comptime std.debug.assert(P.PoolTag == u32);
}

test "distinct tags give same-value owned pools distinct handle types" {
    const FirstTag = struct {};
    const SecondTag = struct {};
    const First = TaggedOwnedPool(u32, FirstTag);
    const Second = TaggedOwnedPool(u32, SecondTag);

    comptime std.debug.assert(First.ObjectHandle != Second.ObjectHandle);
    comptime std.debug.assert(First.OwnedHandle != Second.OwnedHandle);
}

test "two pools of the same type can issue identical token bits" {
    // Documented limitation: tags separate pool types and roles, not runtime
    // pool values. A token must be routed to the pool value that issued it.
    const P = OwnedPool(u32);
    var first = P.init(testing.allocator);
    defer first.deinit();
    var second = P.init(testing.allocator);
    defer second.deinit();

    const from_first = try first.create(1);
    const from_second = try second.create(2);
    try testing.expect(from_first.eql(from_second));

    // The wrong pool cannot detect the mix, so it answers for its own object.
    try testing.expect(second.owns(from_first));
    try testing.expectEqual(@as(u32, 2), second.expect(from_first).*);
    try testing.expectEqual(@as(?u32, 1), first.take(from_second));
}

test "handle sizes stay compact under the default options" {
    const P = OwnedPool(u64);
    try testing.expectEqual(@as(usize, 8), @sizeOf(P.ObjectHandle));
    try testing.expectEqual(@as(usize, 16), @sizeOf(P.OwnedHandle));
    try testing.expectEqual(@as(usize, 8), @sizeOf(ownership.OwnershipState(u64)));
}

test "the pointer guard costs no space in unsafe builds" {
    switch (builtin.mode) {
        .ReleaseFast, .ReleaseSmall => {
            try testing.expectEqual(@as(usize, 0), @sizeOf(std.debug.SafetyLock));
            // Applying a 64-bit constant to a 32-bit target would be wrong.
            if (@sizeOf(usize) == 8) {
                try testing.expectEqual(@as(usize, 56), @sizeOf(OwnedPool(u8)));
            }
        },
        .Debug, .ReleaseSafe => try testing.expect(@sizeOf(std.debug.SafetyLock) > 0),
    }
}

test "the pointer lock permits create, access, and predicates" {
    const P = OwnedPoolWithOptions(u32, .{ .chunk_len = 1 });
    var owned_pool = P.init(testing.allocator);
    defer owned_pool.deinit();

    const token = try owned_pool.create(1);
    owned_pool.lockPointers();
    const pointer = owned_pool.expect(token);

    // Creating another chunk does not move an existing slot.
    _ = try owned_pool.create(2);
    try testing.expectEqual(@intFromPtr(pointer), @intFromPtr(owned_pool.get(token).?));
    try testing.expectEqual(@as(u32, 1), pointer.*);
    try testing.expect(owned_pool.owns(token));
    try testing.expect(owned_pool.contains(token.object()));
    try testing.expectEqual(@as(u32, 2), owned_pool.liveCount());
    owned_pool.unlockPointers();

    // Mutation is allowed again once the pointer lifetime is over.
    try testing.expectEqual(@as(?u32, 1), owned_pool.take(token));
    owned_pool.clearRetainingCapacity();
}
