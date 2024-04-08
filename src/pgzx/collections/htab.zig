//! Implement type safe Postgres HTAB API defined in hsearch.h.
//!
//! hsearch provides support for dynamic hash tables. The hash table can
//! optionally be configured to use shared memory allocated during the
//! extension setup.

const std = @import("std");

const c = @import("../c.zig");
const err = @import("../err.zig");
const meta = @import("../meta.zig");

// Configure how the hash value if to be computed.
const HashValueFunc = union(enum) {
    Strings,
    Blobs,
    Func: c.HashValueFunc,
};

const DirConfig = struct {
    init_size: isize, // (initial) directory size
    max_dsize: isize = c.NO_MAX_DSIZE, // limit to dsize if dir size is limited
};

/// HTab is a type safe wrapper around the Postgres HTAB hash table API.
/// When initializing and working with HTAB one always operates on the KV pair, which we represent as Entry.
/// Initialize the `keysize` to match the field size of your Entry's key type.
pub fn HTab(comptime Context: type) type {
    return struct {
        htab: *c.HTAB,

        pub const Entry = Context.Entry;
        pub const Key = Context.Key;

        const KeyPtr = if (meta.isSlice(Key)) Key else *Key;
        const ConstKeyPtr = if (meta.isSlice(Key)) Key else *const Key;

        const Iterator = HTabIter(Context);
        const ValuesIterator = HTabValuesIter(Context);

        const Self = @This();

        pub const EntryResult = struct {
            found: bool,
            ptr: *Entry,
        };

        pub const Options = struct {
            keysize: ?usize = null, // hash key length in bytes. The hash key is assumed to be the first field in Entry.
            entrysize: ?usize = null, // total user element size in bytes

            num_partitions: ?usize = null, // # partitions (must be power of 2)
            segment_size: ?usize = null, // # entries in a segment
            dir: ?DirConfig = null, // directory size and max size
            hash: HashValueFunc = Context.DefaultHash, // hash function
            match: c.HashCompareFunc = null, // key comparison function
            keycopy: c.HashCopyFunc = null, // key copying function
            alloc: c.HashAllocFunc = null, // memory allocator
            memctx: c.MemoryContext = null, // memory context to use for allocations

            pub fn getSharedSize(self: Options) usize {
                const hctl = self.initHashCtl();
                const flags = self.initFlags();
                return c.hash_get_shared_size(&hctl, flags);
            }

            pub fn initHashCtl(self: Options) c.HASHCTL {
                return .{
                    .num_partitions = @intCast(self.num_partitions orelse 0),
                    .ssize = @intCast(self.segment_size orelse 0),
                    .dsize = @intCast(if (self.dir) |d| d.init_size else 0),
                    .max_dsize = @intCast(if (self.dir) |d| d.max_dsize else c.NO_MAX_DSIZE),
                    .keysize = @intCast(if (self.keysize) |k| k else Context.keySize()),
                    .entrysize = @intCast(if (self.entrysize) |e| e else Context.entrySize()),
                    .hash = if (self.hash == .Func) self.hash.Func else null,
                    .match = self.match,
                    .keycopy = self.keycopy,
                    .alloc = self.alloc,
                    .hcxt = self.memctx,
                    .hctl = null,
                };
            }

            pub fn initFlags(self: Options) c_int {
                var flags: c_int = c.HASH_ELEM;
                flags |= if (self.num_partitions != null) c.HASH_PARTITION else 0;
                flags |= if (self.segment_size != null) c.HASH_SEGMENT else 0;
                flags |= if (self.dir != null) c.HASH_DIRSIZE else 0;
                flags |= switch (self.hash) {
                    .Strings => c.HASH_STRINGS,
                    .Blobs => c.HASH_BLOBS,
                    .Func => c.HASH_FUNCTION,
                };
                flags |= if (self.match != null) c.HASH_COMPARE else 0;
                flags |= if (self.keycopy != null) c.HASH_KEYCOPY else 0;
                flags |= if (self.alloc != null) c.HASH_ALLOC else 0;
                flags |= if (self.memctx != null) c.HASH_CONTEXT else 0;
                return flags;
            }
        };

        pub inline fn init(name: [:0]const u8, nelem: usize, options: Options) !Self {
            const hctl = options.initHashCtl();
            const flags = options.initFlags();

            const created = try err.wrap(c.hash_create, .{ name, @as(c_long, @intCast(nelem)), &hctl, flags });
            return Self.initFrom(created.?);
        }

        /// Initialize a shared memory hash table. Hash tables in shared memory
        /// can not be expanded on the fly. The size settings should be  a good
        /// of what the worker will need.
        pub inline fn initShmem(name: [:0]const u8, init_size: usize, max_size: usize, options: Options) !Self {
            const hctl = options.initHashCtl();
            const flags = options.initFlags();
            const created = try err.wrap(c.ShmemInitHash, .{
                name,
                @as(c_long, @intCast(init_size)),
                @as(c_long, @intCast(max_size)),
                &hctl,
                flags,
            });
            return Self.initFrom(created.?);
        }

        // Initialize from an existing hash table pointer.
        pub inline fn initFrom(htable: *c.HTAB) Self {
            return .{ .htab = htable };
        }

        pub inline fn deinit(self: Self) void {
            c.hash_destroy(self.htab);
        }

        pub fn asPtr(self: Self) *c.HTAB {
            return self.htab;
        }

        pub fn freeze(self: Self) void {
            c.hash_freeze(self.htab);
        }

        /// Compute the hash value for a given key.
        pub fn getHashValue(self: Self, key: ConstKeyPtr) u32 {
            return c.get_hash_value(self.htab, key);
        }

        pub fn count(self: Self) usize {
            return @intCast(c.hash_get_num_entries(self.htab));
        }

        pub fn getRawEntryPointer(self: Self, key: ?*const anyopaque, found: ?*bool) ?*anyopaque {
            return c.hash_search(self.htab, key, c.HASH_FIND, found);
        }

        pub fn getOrPutRawEntryPointer(self: Self, key: ?*const anyopaque, found: ?*bool) error{OutOfMemory}!?*anyopaque {
            const p = c.hash_search(self.htab, key, c.HASH_ENTER_NULL, found);
            if (p == null) {
                return error.OutOfMemory;
            }
            return p;
        }

        pub fn getEntry(self: Self, key: ConstKeyPtr) ?EntryResult {
            var found = false;
            const p = self.getRawEntryPointer(Self.keyPtr(key), &found);
            if (!found) {
                return null;
            }
            return .{ .found = found, .ptr = @ptrCast(@alignCast(p)) };
        }

        pub fn getOrPutEntry(self: Self, key: ConstKeyPtr) error{OutOfMemory}!EntryResult {
            var found: bool = undefined;
            const p = try self.getOrPutRawEntryPointer(Self.keyPtr(key), &found);
            return .{ .found = found, .ptr = @ptrCast(@alignCast(p)) };
        }

        pub fn contains(self: Self, key: ConstKeyPtr) bool {
            var found: bool = undefined;
            _ = self.getRawEntryPointer(Self.keyPtr(key), &found);
            return found;
        }

        pub fn put(self: Self, key: ConstKeyPtr, value: Context.Value) error{OutOfMemory}!void {
            assertContextHasValue();

            const entry = try self.getOrPutEntry(key);
            Context.writeValue(entry.ptr, value);
        }

        pub fn remove(self: Self, key: ConstKeyPtr) bool {
            var found: bool = undefined;
            _ = c.hash_search(self.htab, Self.keyPtr(key), c.HASH_REMOVE, &found);
            return found;
        }

        /// Initialize an iterator for the hash table.
        /// If the iterator was not full exhausted, it should be terminated with `term`.
        pub fn iterator(self: Self) Iterator {
            return Iterator.init(self.htab);
        }

        /// Initialize a values iterator.
        ///
        /// NOTE:
        /// The iterator type is only valid for Contexts that have a readValue function.
        /// This is not the case when using tables that
        /// use Postgres internal structures or are passed to you from
        /// Postgres.
        /// The KVContext and StringKeyContext introduced by pgzx are safe to
        /// use with this iterator.
        pub fn valuesIterator(self: Self) ValuesIterator {
            return ValuesIterator.init(self.htab);
        }

        fn keyPtr(k: ConstKeyPtr) ?*anyopaque {
            if (meta.isSlice(Key)) {
                return @constCast(@ptrCast(k.ptr));
            }
            return @constCast(k);
        }

        inline fn assertContextHasValue() void {
            if (!conextHasValue()) {
                @compileError("Context must have a 'Value' field and a 'writeValue' function");
            }
        }

        inline fn conextHasValue() bool {
            switch (@typeInfo(Context)) {
                .Struct => {},
                else => return false,
            }
            if (!@hasDecl(Context, "Value")) {
                return false;
            }
            return std.meta.hasFn(Context, "writeValue");
        }
    };
}

// Iterator for Postgres HTAB has tables.
//
// In case the iteration is not full exhausted, it should be terminated with `term`.
pub fn HTabIter(comptime Context: type) type {
    return struct {
        status: c.HASH_SEQ_STATUS,

        const Self = @This();

        pub fn init(htab: *c.HTAB) Self {
            // SAFETY:
            //   The status type is initialized by the hash_seq_init function only.
            //   It only holds a pointer into HTAB but is not self referential
            //   and the pointer to status is not stored anywhere else.
            //
            //   It is safe to move the 'status', but it SHOULD NOT be copied.
            //   If the hash table is not frozen Postgres keeps track
            var status: c.HASH_SEQ_STATUS = undefined;
            c.hash_seq_init(&status, htab);
            return .{ .status = status };
        }

        // Terminates the iteration. Use `term` if you want to stop the iteration early.
        //
        // WARNING:
        // Do not call `term` after `next` has returned null.
        // Postgres automatically calls hash_seq_term when the iteration is
        // done. Terminating the iterator again can break bookeeping of active
        // scans in Postgres, which eventually resuls in an error being thrown
        // either now, or by some other iteration.
        pub fn term(self: *Self) void {
            c.hash_seq_term(&self.status);
        }

        // Get the pointer to the next entry in the hash table.
        //
        // Returns null if the iteration is done. The iterator is automatically
        // terminated in this case and one must not use the `term` method.
        pub fn next(self: *Self) ?*Context.Entry {
            const p = c.hash_seq_search(&self.status);
            if (p == null) {
                return null;
            }
            return @ptrCast(@alignCast(p));
        }
    };
}

pub fn HTabValuesIter(comptime Context: type) type {
    return struct {
        iter: HTabIter(Context),

        pub const Self = @This();

        pub fn init(htab: *c.HTAB) Self {
            return .{ .iter = HTabIter(Context).init(htab) };
        }

        pub fn term(self: *Self) void {
            self.iter.term();
        }

        pub fn next(self: *Self) ?Context.Value {
            const entry = self.iter.next();
            return if (entry) |e| Context.readValue(e) else null;
        }
    };
}

pub const StringKeyOptions = struct {
    max_str_len: usize = c.NAMEDATALEN,
};

// Create a hash table with string keys. The key is stored in a fixed size array in the hash table entry. Use `max_str_len` to configure the maximum supported string length.
//
// WARNING: If the buffer size is not sufficient, the hash table will store the
// prefix of the input string only.
pub fn StringHashTable(comptime V: type, comptime options: StringKeyOptions) type {
    return HTab(StringKeyContext(V, options));
}

pub fn StringKeyContext(comptime V: type, comptime options: StringKeyOptions) type {
    return struct {
        pub const Key = [:0]const u8;
        pub const Value = V;

        pub const DefaultHash = HashValueFunc.Strings;

        pub const Entry = extern struct {
            key: [options.max_str_len]u8,
            value: V,
        };

        pub fn keySize() usize {
            return options.max_str_len;
        }

        pub fn entrySize() usize {
            return @sizeOf(Entry);
        }

        pub fn writeValue(entry: *Entry, value: V) void {
            entry.*.value = value;
        }

        pub fn readValue(entry: *Entry) V {
            return entry.*.value;
        }
    };
}

// Create a hash table of key-value pairs.
//
// The entries of the hash table will store the tuple into a struct with fields `key` and `value`.
//
// The `key` value is expected to be copied into the struct. Do not use use
// pointers or struct that store pointers for `K`.
pub fn KVHashTable(comptime K: type, comptime V: type) type {
    return HTab(KVContext(K, V));
}

pub fn KVContext(comptime K: type, comptime V: type) type {
    return struct {
        pub const Key = K;
        pub const Value = V;

        pub const DefaultHash = HashValueFunc.Blobs;

        pub const Entry = extern struct {
            key: K,
            value: V,
        };

        pub fn keySize() usize {
            return @sizeOf(K);
        }

        pub fn entrySize() usize {
            return @sizeOf(Entry);
        }

        pub fn writeValue(entry: *Entry, value: V) void {
            entry.*.value = value;
        }

        pub fn readValue(entry: *Entry) V {
            return entry.*.value;
        }
    };
}

pub inline fn KeyPtr(comptime K: type) type {
    // Slices are fat pointers. So we accept them as is.
    if (meta.isSlice(K)) {
        return K;
    }
    return *const K;
}

inline fn keyPtr(comptime K: type, k: KeyPtr(K)) ?*anyopaque {
    if (meta.isSlice(K)) {
        return @constCast(@ptrCast(k.ptr));
    }
    return @constCast(k);
}

pub const TestSuite_HTab = struct {
    const IntTable = KVHashTable(u32, u32);
    const StringTable = StringHashTable(u32, .{});

    pub fn testInitInt() !void {
        var table = try IntTable.init("testing table", 2, .{});
        defer table.deinit();

        try std.testing.expectEqual(table.count(), 0);

        const k: u32 = 42;
        try std.testing.expectEqual(table.contains(&k), false);
    }

    pub fn testInitString() !void {
        var table = try StringTable.init("testing table", 2, .{});
        defer table.deinit();

        try std.testing.expectEqual(table.count(), 0);
        try std.testing.expectEqual(table.contains("foo"), false);
    }

    pub fn testGetOrPutEntryInt() !void {
        var table = try IntTable.init("testing table", 2, .{});
        defer table.deinit();

        {
            const k: u32 = 42;
            const entry = try table.getOrPutEntry(&k);
            try std.testing.expectEqual(entry.found, false);
            entry.ptr.*.value = 24;
        }

        {
            const k: u32 = 42;
            const entry = try table.getOrPutEntry(&k);
            try std.testing.expectEqual(entry.found, true);
            try std.testing.expectEqual(entry.ptr.*.value, 24);
        }

        {
            const k: u32 = 42;
            const optEntry = table.getEntry(&k);
            try std.testing.expect(optEntry != null);
            try std.testing.expectEqual(optEntry.?.found, true);
            try std.testing.expectEqual(optEntry.?.ptr.*.value, 24);
        }

        {
            const k_unknown: u32 = 43;
            const optEntry = table.getEntry(&k_unknown);
            try std.testing.expect(optEntry == null);
        }
    }

    pub fn testGetOrPutEntryString() !void {
        var table = try StringTable.init("testing table", 2, .{});
        defer table.deinit();

        {
            const entry = try table.getOrPutEntry("foo");
            try std.testing.expectEqual(entry.found, false);
            entry.ptr.*.value = 42;
        }

        {
            const entry = try table.getOrPutEntry("foo");
            try std.testing.expectEqual(true, entry.found);
            try std.testing.expectEqual(42, entry.ptr.*.value);
        }

        {
            const optEntry = table.getEntry("foo");
            try std.testing.expect(optEntry != null);
            try std.testing.expectEqual(optEntry.?.found, true);
            try std.testing.expectEqual(optEntry.?.ptr.*.value, 42);
        }

        {
            const optEntry = table.getEntry("bar");
            try std.testing.expect(optEntry == null);
        }
    }

    pub fn testGetOrPutEntryStringWithCustomCallbacks() !void {
        const callbacks = struct {
            fn strcmp(a: ?*const anyopaque, b: ?*const anyopaque, sz: usize) callconv(.C) c_int {
                const char_ptr_a: [*c]const u8 = @ptrCast(a);
                const char_ptr_b: [*c]const u8 = @ptrCast(b);
                const str_a = std.mem.span(char_ptr_a);
                const str_b = std.mem.span(char_ptr_b);

                // std.log.debug("strcmp: a=({*})'{s}', b='{s}', sz={}", .{ a, str_a, str_b, sz });
                // std.log.debug("strcmp: a={any}, b={any}", .{ str_a, str_b });

                return c.strncmp(str_a, str_b, sz);
            }

            fn strcpy(to: ?*anyopaque, from: ?*const anyopaque, sz: usize) callconv(.C) ?*anyopaque {
                const char_ptr_to: [*c]u8 = @ptrCast(to);
                const char_ptr_from: [*c]const u8 = @ptrCast(from);

                // const str_from = std.mem.span(char_ptr_from);
                // std.log.debug("strcpy:  to={*}, from='{s}', sz={}", .{ to, str_from, sz });

                _ = c.strlcpy(char_ptr_to, char_ptr_from, @intCast(sz));
                return to;
            }
        };

        var table = try StringTable.init("testing table", 2, .{
            .keysize = 4,
            .match = callbacks.strcmp,
            .keycopy = callbacks.strcpy,
        });
        defer table.deinit();

        {
            const entry = try table.getOrPutEntry("foo");
            try std.testing.expectEqual(entry.found, false);
            entry.ptr.*.value = 42;
        }

        {
            const entry = try table.getOrPutEntry("foo");
            try std.testing.expectEqual(true, entry.found);
            try std.testing.expectEqual(42, entry.ptr.*.value);
        }

        {
            const optEntry = table.getEntry("foo");
            try std.testing.expect(optEntry != null);
            try std.testing.expectEqual(optEntry.?.found, true);
            try std.testing.expectEqual(optEntry.?.ptr.*.value, 42);
        }

        {
            const optEntry = table.getEntry("bar");
            try std.testing.expect(optEntry == null);
        }
    }

    pub fn testContainsInt() !void {
        var table = try IntTable.init("testing table", 2, .{});
        defer table.deinit();

        const k: u32 = 42;
        try table.put(&k, 24);

        {
            try std.testing.expectEqual(table.contains(&k), true);
        }

        {
            const k_unknown: u32 = 43;
            try std.testing.expectEqual(table.contains(&k_unknown), false);
        }
    }

    pub fn testContainsString() !void {
        var table = try StringTable.init("testing table", 2, .{});
        defer table.deinit();

        try table.put("foo", 24);
        try std.testing.expectEqual(table.contains("foo"), true);
        try std.testing.expectEqual(table.contains("bar"), false);
    }

    pub fn testRemoveInt() !void {
        var table = try IntTable.init("testing table", 2, .{});
        defer table.deinit();

        const k: u32 = 42;
        try table.put(&k, 24);
        try std.testing.expectEqual(table.contains(&k), true);

        try std.testing.expectEqual(table.remove(&k), true);
        try std.testing.expectEqual(table.contains(&k), false);
    }

    pub fn testRemoveString() !void {
        var table = try StringTable.init("testing table", 2, .{});
        defer table.deinit();

        try table.put("foo", 24);
        try std.testing.expectEqual(table.contains("foo"), true);

        try std.testing.expectEqual(table.remove("foo"), true);
        try std.testing.expectEqual(table.contains("foo"), false);
    }

    pub fn testIterInt() !void {
        var table = try IntTable.init("testing table", 2, .{});
        defer table.deinit();

        const k1: u32 = 42;
        const k2: u32 = 43;
        try table.put(&k1, 24);
        try table.put(&k2, 25);

        var count: u32 = 0;
        var iter = table.iterator();
        while (iter.next()) |_| {
            count += 1;
        }
        try std.testing.expectEqual(count, 2);
    }

    pub fn testIterValuesInt() !void {
        var table = try IntTable.init("testing table", 2, .{});
        defer table.deinit();

        const k1: u32 = 42;
        const k2: u32 = 43;
        try table.put(&k1, 0);
        try table.put(&k2, 1);

        var seen = [_]bool{ false, false };
        var count: usize = 0;
        var iter = table.valuesIterator();
        while (iter.next()) |value| {
            count += 1;
            try std.testing.expect(value < 2);
            seen[value] = true;
        }

        try std.testing.expectEqual(count, 2);
        try std.testing.expectEqual(seen, [_]bool{ true, true });
    }

    pub fn testIterValueString() !void {
        var table = try StringTable.init("testing table", 2, .{});

        try table.put("foo", 0);
        try table.put("bar", 1);

        var seen = [_]bool{ false, false };
        var count: usize = 0;
        var iter = table.valuesIterator();
        while (iter.next()) |value| {
            count += 1;
            try std.testing.expect(value < 2);
            seen[value] = true;
        }

        try std.testing.expectEqual(count, 2);
        try std.testing.expectEqual(seen, [_]bool{ true, true });
    }
};
