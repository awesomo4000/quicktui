<!-- SPDX-License-Identifier: MPL-2.0 -->

<p align="center">
  <img src="img/poolside.png" alt="Poolside generational handle pools" width="600" height="300">
</p>

# poolside

`poolside` is a Zig 0.16 library for stable, generational handle pools. It
turns stale references into a checked condition while keeping graph-shaped
data, cycles, and parent pointers straightforward.

```zig
const std = @import("std");
const poolside = @import("poolside");

const Nodes = poolside.Pool(Node);
const Node = struct {
    value: u32,
    parent: Nodes.Handle = Nodes.Handle.none,
};

var nodes = Nodes.init(allocator);
defer nodes.deinit();

const handle = try nodes.create(.{ .value = 42 });
nodes.expect(handle).value += 1;
_ = nodes.discardAt(handle, @src());
std.debug.assert(nodes.get(handle) == null);
```

The core guarantees are:

- Slot addresses never move. Storage grows in independently allocated chunks.
- Slots share chunk allocations. Ending one object never frees its storage.
- Odd generations are live; even generations are free.
- Reuse changes the generation, so an old handle cannot resolve to a new value.
- Generation zero is retired permanently, preventing wraparound ABA bugs.
- `take` and `discard` reject stale, forged, and free-slot handles.

Use `get` when staleness is expected and `expect` when it is an invariant
violation. `createAt`, `takeAt`, and `discardAt` accept `@src()` for Debug
provenance; `clearRetainingCapacityAt` does the same for a pool reset. The
shorter variants omit source capture.

## Storage and allocation

Poolside has arena-like allocation behavior with reusable slots. It allocates
fixed-size chunks, 512 slots by default, and keeps ended slots on a free list.
It never allocates or frees storage for one object at a time.

`OwnedPool` uses the same chunks and stores each ownership epoch beside its
value. Tokens are ordinary values and do not point to separately allocated
ownership state.

- `create` first reuses a free slot. It allocates only when the pool needs
  another chunk or must grow its chunk-pointer list.
- `contains`, accessors, iteration, `take`, and `discard` do not allocate.
- `OwnedPool.transfer` and all ownership checks do not allocate.
- `take` and `discard` return a slot to the free list, or retire it when its
  generation wraps, without freeing memory.
- `clearRetainingCapacity` ends every live object and keeps every chunk.
- Pool `deinit` frees the chunks and bookkeeping storage in one pass.

`liveCount` reports current objects. `slotCount` is the initialized slot
high-water mark, including free and retired slots but not unused positions in
the last chunk. `retiredCount` reports slots whose generation counters wrapped
to zero and can never be reused.

`PoolWithOptions` accepts `chunk_len`, `generation_bits`, and
`track_provenance`. `OwnedPoolWithOptions` adds `ownership_bits`. The generation
and ownership widths must each be between 2 and 64 bits. Smaller widths are
useful for testing exhaustion; the defaults are 32-bit object generations and
64-bit ownership epochs. `track_provenance` defaults to enabled in Debug and
disabled in other build modes.

The pool index is 32 bits. If every possible index has been introduced,
`create` returns `error.OutOfCapacity` even if the allocator has memory left.

## Payload lifetimes

Poolside manages pool storage. It never deinitializes payloads and never calls
a method on `T`, including any declaration named `deinit`.

`take` transfers the stored value to the caller and ends the object's lifetime:

```zig
if (pool.take(handle)) |taken| {
    var value = taken;
    value.deinit(value_allocator);
}
```

`discard` ends a lifetime without reading the slot. Use it for plain values, or
for a value already cleaned in place through its stable address:

```zig
if (pool.get(handle)) |value| {
    value.deinit(value_allocator);
    _ = pool.discard(handle);
}
```

`clearRetainingCapacity` and `Pool.deinit` discard payload bits without reading
them. Callers holding resource-owning payloads must clean them first:

```zig
var entries = pool.iterator();
while (entries.next()) |entry| {
    entry.value.deinit(value_allocator);
}
pool.clearRetainingCapacity();
```

If `create` returns an error, the pool never accepted the value, so the caller
still owns it.

## Provenance and diagnostics

The `At` variants record the supplied source location when provenance is
enabled. `provenance` returns slot-oriented diagnostics, including the current
generation, whether the slot is live, and its most recent creation and
end-of-lifetime sites. It returns `null` when provenance is disabled, the
handle is `none`, or the index has never existed.

Owned-pool provenance also reports the current ownership epoch and the site
that issued it. A stale `expect` distinguishes an ended object lifetime from a
live object whose authority moved to another epoch. Provenance is diagnostic
information, not an ownership token or a security boundary.

## Ownership

`OwnedPool(T)` adds dynamically checked unique ownership on top of the same
storage. An object keeps one stable identity for its whole lifetime, while
authority over it rotates through ownership epochs. Only a token carrying the
current epoch may access, transfer, take, or discard the object.

```zig
const Buffers = poolside.TaggedOwnedPool(Buffer, struct {});

var buffers = Buffers.init(allocator);
defer buffers.deinit();

// The creator is the first owner, at epoch one.
var producer = try buffers.createAt(buffer, @src());
const object = producer.object();

// Hand authority to the I/O service. The payload does not move.
var io_token = try buffers.transferAt(&producer, @src());
std.debug.assert(producer.isCleared());
std.debug.assert(buffers.contains(object));

// A copy of an older token is stale, even though the object is alive.
const old_copy = io_token;
const consumer = try buffers.transferAt(&io_token, @src());
std.debug.assert(buffers.get(old_copy) == null);
std.debug.assert(buffers.owns(consumer));

// Only the current owner can take the payload, and only once.
var taken = buffers.takeAt(consumer, @src()).?;
taken.deinit(buffer_allocator);
std.debug.assert(!buffers.contains(object));
```

`ObjectHandle` is a non-owning identity for logs, graphs, and operation
tables. It answers `contains` and `provenance` but grants no payload access.

Cleaning a value in place works the same way as with `Pool`:

```zig
if (buffers.get(owned)) |value| {
    value.deinit(buffer_allocator);
    _ = buffers.discard(owned);
}
```

Failures are distinguishable rather than merged. `transfer` returns
`error.StaleObject` when the object is gone, `error.StaleOwnership` when the
token's epoch is not current, and `error.OwnershipExhausted` when the epoch
counter is at its maximum. Accessors return `null` for a gone object or a
non-current epoch, and `expect` panics with a message naming either the site
where the lifetime ended or the handoff that issued the current epoch.
Exhaustion is not a revocation and has no accessor equivalent: only `transfer`
reports it, and the current token still reads, takes, and discards.

Ownership is a checked protocol, not a language guarantee. A token is an
ordinary copyable value, so trusted code can construct one; the pool validates
every token before use. Poolside catches stale and confused uses, and is not a
security boundary against deliberate fabrication.

The raw-pointer boundary matters here. A pointer from `get` or `expect` is
checked when it is obtained, and holding it bypasses every later check. Across
a transfer it still points at valid memory holding the same value, but it is no
longer authorized by the ownership protocol. Take, discard, and clear end the
value it points at, and a later create may reuse that slot, so the pointer can
expose a different object. Pool deinit frees the chunk outright and leaves the
pointer dangling. Both pools are deliberately single-threaded and add no
locking: serialize every operation, and ensure no returned pointer is in use
when another thread changes an object's ownership or lifetime.

## Standalone ownership

`OwnedHandle(ObjectHandle, Epoch, Tag)` and `OwnershipState(Epoch)` can add the
same epoch protocol to resources stored outside a pool. They use no allocator
and have no dependency on `Pool` or `OwnedPool`.

```zig
const SessionId = struct { value: u64 };
const SessionTag = struct {};
const SessionToken = poolside.OwnedHandle(SessionId, u32, SessionTag);
const SessionState = poolside.OwnershipState(u32);

var state = SessionState.init();
var producer = SessionToken.init(.{ .value = 42 }, state.current());

const next_epoch = try state.transfer(producer.ownership_epoch);
const consumer = SessionToken.init(producer.object(), next_epoch);
producer.clear();

std.debug.assert(producer.isCleared());
std.debug.assert(state.matches(consumer.ownership_epoch));
```

The authority manager must validate object lifetime separately. Do not reset
an `OwnershipState` to epoch one while reusing the same object identifier. That
would allow an old epoch-one token to become current again.

## Iterator and pointer lifetimes

These rules are part of the API contract in every build mode:

- Do not create, take, discard, clear, or deinitialize the pool while an
  iterator is active. Collect handles first and mutate afterward.
- `create` never moves an existing slot or invalidates a pointer, but an
  iterator continued across `create` has unspecified completeness and order.
- `take`, `discard`, `clearRetainingCapacity`, and `deinit` may invalidate
  pointers already returned by an accessor or an iterator.
- Return a handle to the runtime pool value that issued it.

The same rules apply to `OwnedPool`, where the guard also covers `transfer`,
because a transfer revokes the authority under which a pointer was obtained.
An owned iterator returns a current `OwnedHandle` with each value, which creates
another copy of that object's authority. A token collected before a transfer
becomes stale afterward.

`lockPointers` and `unlockPointers` are an opt-in diagnostic for the pointer
half of those rules, backed by `std.debug.SafetyLock`:

```zig
pool.lockPointers();
const value = pool.expect(handle);
defer pool.unlockPointers();
```

While locked, `take`, `discard`, `clearRetainingCapacity`, and `deinit` fail
the safety check in Debug and ReleaseSafe. `create`, accessors, provenance, and
iteration stay allowed. `OwnedPool.transfer` also fails while locked. The lock
is not nestable, adds no state in ReleaseFast or ReleaseSmall, and does not
diagnose the iterator rule above.

## Scope

Poolside does not provide reachability analysis and does not inspect payload
graphs. Handles, pointers, slices, cycles, and hash maps inside a payload are
ordinary data with no automatic lifetime behavior. Applications that need leak
detection can implement it against their own edge representation and root set.

Fields such as the inner pool are implementation state. Zig does not enforce
field privacy, so these guarantees describe the documented methods and returned
types; code that reaches through undocumented fields is outside the contract,
like code that fabricates a token or retains a pointer past its lifetime.

Handles are always relative to a particular pool value. When a program owns
multiple pools containing the same `T`, use `TaggedPool(T, Tag)` or
`TaggedOwnedPool(T, Tag)` with a unique tag type for each pool role. Their
handle types then cannot be mixed. Tags separate pool types and roles, not two
values of the same pool type. Handles from two such pools can have identical
bits, and neither pool can detect the mix.

## License

Original Poolside code is licensed under the [Mozilla Public License 2.0](LICENSE).
When MPL-covered Poolside files are distributed with modifications, those
files and their modifications must remain available under MPL-2.0. Separate
applications and source files that merely import, link to, or use Poolside may
remain proprietary or use another license.

## Commands

```sh
zig build
zig build test
zig build bench
```

`zig build test` runs the suite in Debug, ReleaseSafe, ReleaseFast, and
ReleaseSmall, and it owns the compile-failure and expected-safety-failure
fixtures under `test/`. The ReleaseFast benchmark compares plain and owned
access, take, and discard for 16-byte and 512-byte payloads, and measures owned
transfer. `take` returns `T` by value, so its cost naturally grows with payload
size.

The pool is deliberately single-threaded; concurrent lifetime changes cannot
safely coexist with an API that returns pointers into slots.

Iteration skips free slots and costs time proportional to the high-water mark.
