// SPDX-License-Identifier: MPL-2.0

//! Standalone ownership tokens and authority state.
//!
//! These types carry no allocator and no pool dependency. An authority manager
//! treats `OwnershipState` as implementation state, hands out `OwnedHandle`
//! values, and validates every operation against the stored epoch. The check
//! is dynamic, not unforgeable: trusted code can construct a token, so these
//! types catch stale and confused uses rather than deliberate fabrication.

const std = @import("std");

/// A copyable token pairing an object identity with a claimed ownership epoch.
/// It stores no authoritative state and validates nothing itself. `Tag` brands
/// unrelated ownership domains at compile time and costs no storage.
pub fn OwnedHandle(
    comptime ObjectHandle: type,
    comptime Epoch: type,
    comptime Tag: type,
) type {
    comptime validateEpochType(Epoch);

    return struct {
        const Self = @This();

        /// The object-identity type this token carries.
        pub const Object = ObjectHandle;
        /// The epoch integer type.
        pub const OwnershipEpoch = Epoch;
        /// The type this token is branded with.
        pub const OwnershipTag = Tag;

        /// The resource identity. It remains available after `clear` for
        /// routing and diagnostics.
        object_handle: ObjectHandle,

        /// The claimed epoch. Zero means this token variable is cleared.
        ownership_epoch: Epoch,

        /// Intended for authority-manager implementations. Ordinary pool users
        /// should only hold tokens returned by their authority manager.
        pub fn init(object_handle: ObjectHandle, epoch: Epoch) Self {
            return .{ .object_handle = object_handle, .ownership_epoch = epoch };
        }

        /// Compares both object identity and claimed ownership epoch.
        pub fn eql(a: Self, b: Self) bool {
            return a.ownership_epoch == b.ownership_epoch and
                std.meta.eql(a.object_handle, b.object_handle);
        }

        /// A pure projection. It returns the embedded object identity even for
        /// a stale or cleared token, which keeps it useful for diagnostics.
        pub fn object(handle: Self) ObjectHandle {
            return handle.object_handle;
        }

        /// Epoch zero carries no ownership claim. A token that is not cleared
        /// is not thereby current; only the authority manager can say that.
        pub fn isCleared(handle: Self) bool {
            return handle.ownership_epoch == 0;
        }

        /// Removes this variable's claim while retaining object identity. Other
        /// copies are unaffected; they go stale when the authority advances.
        pub fn clear(handle: *Self) void {
            handle.ownership_epoch = 0;
        }
    };
}

/// The authoritative ownership epoch for one object. It starts at one, rejects
/// epoch zero, advances only for a matching claim, and never wraps.
///
/// This type does not manage object lifetime. An authority manager must use
/// object identifiers that change when a resource lifetime ends, or otherwise
/// keep ownership history non-repeating across reuse: resetting the state to
/// epoch one while reusing an object identifier can make an old token valid
/// again.
pub fn OwnershipState(comptime Epoch: type) type {
    comptime validateEpochType(Epoch);

    return struct {
        const Self = @This();

        /// The epoch integer type.
        pub const OwnershipEpoch = Epoch;
        /// A claim that is not current, or a counter at its maximum. Both
        /// leave the state unchanged.
        pub const TransferError = error{
            StaleOwnership,
            OwnershipExhausted,
        };

        /// The epoch every new object starts at. Zero means "cleared".
        const first_epoch: Epoch = 1;

        current_epoch: Epoch = first_epoch,

        /// Starts a new ownership sequence at epoch one.
        pub fn init() Self {
            return .{};
        }

        /// Returns the epoch accepted by `matches` and `transfer`.
        pub fn current(state: Self) Epoch {
            return state.current_epoch;
        }

        /// Returns whether a nonzero claim is the current epoch.
        pub fn matches(state: Self, claimed_epoch: Epoch) bool {
            return claimed_epoch != 0 and claimed_epoch == state.current_epoch;
        }

        /// Validates `claimed_epoch`, advances the state, and returns the new
        /// epoch. Failure leaves the state unchanged.
        ///
        /// The claim is checked before exhaustion, so a stale token presented
        /// to an exhausted state reports `error.StaleOwnership`.
        pub fn transfer(state: *Self, claimed_epoch: Epoch) TransferError!Epoch {
            if (!state.matches(claimed_epoch)) return error.StaleOwnership;
            if (state.current_epoch == std.math.maxInt(Epoch)) return error.OwnershipExhausted;
            state.current_epoch += 1;
            return state.current_epoch;
        }
    };
}

fn validateEpochType(comptime Epoch: type) void {
    const info = @typeInfo(Epoch);
    if (info != .int) {
        @compileError(
            "poolside ownership epoch must be an unsigned integer, found " ++ @typeName(Epoch),
        );
    }
    if (info.int.signedness != .unsigned) {
        @compileError(
            "poolside ownership epoch must be an unsigned integer, found " ++ @typeName(Epoch),
        );
    }
    if (info.int.bits < 2 or info.int.bits > 64) {
        @compileError("poolside ownership epoch must have between 2 and 64 bits");
    }
}

const testing = std.testing;

const SessionId = struct { value: u64 };
const SessionOwnership = struct {};
const SessionToken = OwnedHandle(SessionId, u64, SessionOwnership);
const SessionState = OwnershipState(u64);

test "a new state starts at epoch one and rejects every other claim" {
    var state = SessionState.init();
    try testing.expectEqual(@as(u64, 1), state.current());
    try testing.expect(state.matches(1));

    // Epoch zero is the cleared marker and never a valid claim.
    try testing.expect(!state.matches(0));
    try testing.expect(!state.matches(2));
    try testing.expect(!state.matches(std.math.maxInt(u64)));
}

test "transfer returns the next epoch and invalidates the previous one" {
    var state = SessionState.init();
    const second = try state.transfer(1);
    try testing.expectEqual(@as(u64, 2), second);
    try testing.expectEqual(@as(u64, 2), state.current());
    try testing.expect(!state.matches(1));
    try testing.expect(state.matches(2));

    const third = try state.transfer(second);
    try testing.expectEqual(@as(u64, 3), third);
    try testing.expect(!state.matches(2));
}

test "a stale or cleared claim leaves the state unchanged" {
    var state = SessionState.init();
    _ = try state.transfer(1);

    try testing.expectError(error.StaleOwnership, state.transfer(1));
    try testing.expectError(error.StaleOwnership, state.transfer(0));
    try testing.expectError(error.StaleOwnership, state.transfer(99));
    try testing.expectEqual(@as(u64, 2), state.current());
    try testing.expect(state.matches(2));
}

test "a two-bit epoch reaches three and then reports exhaustion" {
    const Narrow = OwnershipState(u2);
    var state = Narrow.init();
    try testing.expectEqual(@as(u2, 1), state.current());
    try testing.expectEqual(@as(u2, 2), try state.transfer(1));
    try testing.expectEqual(@as(u2, 3), try state.transfer(2));

    // Checked arithmetic, so the epoch never wraps back to zero or one.
    try testing.expectError(error.OwnershipExhausted, state.transfer(3));
    try testing.expectEqual(@as(u2, 3), state.current());
    try testing.expect(state.matches(3));

    // A stale claim against an exhausted state reports staleness first.
    try testing.expectError(error.StaleOwnership, state.transfer(2));
    try testing.expectEqual(@as(u2, 3), state.current());
}

test "clear removes only the epoch and keeps object identity" {
    var token = SessionToken.init(.{ .value = 42 }, 1);
    try testing.expect(!token.isCleared());

    token.clear();
    try testing.expect(token.isCleared());
    try testing.expectEqual(@as(u64, 42), token.object().value);
    try testing.expectEqual(@as(u64, 0), token.ownership_epoch);
}

test "eql compares object identity and epoch" {
    const first = SessionToken.init(.{ .value = 7 }, 3);
    try testing.expect(first.eql(SessionToken.init(.{ .value = 7 }, 3)));
    try testing.expect(!first.eql(SessionToken.init(.{ .value = 7 }, 4)));
    try testing.expect(!first.eql(SessionToken.init(.{ .value = 8 }, 3)));
}

test "distinct tags produce distinct token types without runtime storage" {
    const Devices = struct {};
    const Sessions = struct {};
    const DeviceToken = OwnedHandle(SessionId, u64, Devices);
    const SessionsToken = OwnedHandle(SessionId, u64, Sessions);

    comptime std.debug.assert(DeviceToken != SessionsToken);
    comptime std.debug.assert(DeviceToken.OwnershipTag == Devices);
    try testing.expectEqual(@sizeOf(DeviceToken), @sizeOf(SessionsToken));
    try testing.expectEqual(@as(usize, 16), @sizeOf(DeviceToken));
}

test "a manager hands off authority without touching the object identity" {
    var state = SessionState.init();
    var producer = SessionToken.init(.{ .value = 42 }, state.current());

    const next_epoch = try state.transfer(producer.ownership_epoch);
    const consumer = SessionToken.init(producer.object(), next_epoch);
    producer.clear();

    try testing.expect(producer.isCleared());
    try testing.expect(state.matches(consumer.ownership_epoch));
    try testing.expect(!state.matches(1));
    try testing.expectEqual(producer.object().value, consumer.object().value);
}

test "resetting state while reusing an object identifier revives an old token" {
    // Reference test for the documented hazard. An authority manager must
    // change the object identifier when a resource lifetime ends, the way
    // OwnedPool advances its object generation.
    var state = SessionState.init();
    const stale = SessionToken.init(.{ .value = 1 }, state.current());
    _ = try state.transfer(stale.ownership_epoch);
    try testing.expect(!state.matches(stale.ownership_epoch));

    // The resource ends and a new one reuses both the identifier and a fresh
    // state, so the old token resolves again.
    state = SessionState.init();
    const reused = SessionToken.init(.{ .value = 1 }, state.current());
    try testing.expect(state.matches(stale.ownership_epoch));
    try testing.expect(stale.eql(reused));
}
