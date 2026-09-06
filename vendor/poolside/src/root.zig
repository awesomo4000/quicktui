// SPDX-License-Identifier: MPL-2.0

//! Stable, chunked generational handle pools for Zig.
//!
//! `Pool` provides reusable storage and stale-handle detection. `OwnedPool`
//! adds dynamically checked ownership epochs without changing the chunked
//! allocation model. Standalone `OwnedHandle` and `OwnershipState` types let
//! other resource managers use the same handoff protocol.

pub const Options = @import("pool.zig").Options;
pub const Pool = @import("pool.zig").Pool;
pub const PoolWithOptions = @import("pool.zig").PoolWithOptions;
pub const TaggedPool = @import("pool.zig").TaggedPool;
pub const TaggedPoolWithOptions = @import("pool.zig").TaggedPoolWithOptions;

pub const OwnedHandle = @import("ownership.zig").OwnedHandle;
pub const OwnershipState = @import("ownership.zig").OwnershipState;
pub const OwnedOptions = @import("owned_pool.zig").OwnedOptions;
pub const OwnedPool = @import("owned_pool.zig").OwnedPool;
pub const OwnedPoolWithOptions = @import("owned_pool.zig").OwnedPoolWithOptions;
pub const TaggedOwnedPool = @import("owned_pool.zig").TaggedOwnedPool;
pub const TaggedOwnedPoolWithOptions = @import("owned_pool.zig").TaggedOwnedPoolWithOptions;

test {
    _ = @import("pool.zig");
    _ = @import("ownership.zig");
    _ = @import("owned_pool.zig");
}
