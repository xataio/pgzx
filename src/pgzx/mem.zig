//! Support utilities for Postgres memory management.
//!
//! For more details see:
//! - src/backend/utils/mmgr/README

const std = @import("std");

const c = @import("c.zig");
const err = @import("err.zig");

/// Simple allocator that uses palloc, pfree, and repalloc.
/// These functions will use the current memory context established in the
/// Postgres process. For data structures `MemoryContextAllocator` to ensure that
/// The memory is always allocated and freed on the same memory context.
///
/// The allocator uses MCXT_ALLOC_NO_OOM which will tells the postgres API
/// to not throw an error in case there is not enough memory available.
/// The zig allocation APIs will still return an OutOfMemory error that can
/// be handled internally. If we can't recover from OOM we should capture
/// and throw a memory error ourselves in the error handler.
pub const PGCurrentContextAllocator: std.mem.Allocator = .{
    .ptr = undefined,
    .vtable = &.{
        .alloc = &pg_alloc,
        .free = &pg_free,
        .resize = &pg_resize,
    },
};

fn pg_alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
    _ = ret_addr;
    _ = ctx;
    return @ptrCast(c.palloc_aligned(len, ptr_align, c.MCXT_ALLOC_NO_OOM));
}

fn pg_free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
    _ = ret_addr;
    _ = buf_align;
    _ = ctx;
    c.pfree(@ptrCast(buf));
}

fn pg_resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
    _ = ret_addr;
    _ = new_len;
    _ = buf_align;
    _ = buf;
    _ = ctx;

    // Postgres API only support realloc and might therefore relocate the buffer.
    // resize is not allowed to relocate the buffer, so we have to return false
    // and force the zig allocator to allocate a new buffer.
    return false;
}

pub fn getErrorContext() MemoryContextAllocator {
    return MemoryContextAllocator.init(c.ErrorContext, .{});
}

/// ErrorContext based memory context allocator.
/// The allocator is configure to use PostgreSQL-throw (longjump) on OOM.
pub fn getErrorContextThrowOOM() MemoryContextAllocator {
    return MemoryContextAllocator.init(c.ErrorContext, .{ .flags = 0 });
}

pub const AllocSetOptions = struct {
    parent: c.MemoryContext = null,
    init_size: c.Size = @intCast(c.ALLOCSET_DEFAULT_INITSIZE),
    min_size: c.Size = @intCast(c.ALLOCSET_DEFAULT_MINSIZE),
    max_size: c.Size = @intCast(c.ALLOCSET_DEFAULT_MAXSIZE),

    flags: c_int = MemoryContextAllocator.DEFAULT_FLAGS,
};

/// Create a new AllocSet based memory context.
///
/// If `parent` is null the TopLevel will be used.
pub fn createAllocSetContext(comptime name: [:0]const u8, options: AllocSetOptions) error{PGErrorStack}!MemoryContextAllocator {
    const ctx: c.MemoryContext = try err.wrap(
        c.AllocSetContextCreateInternal,
        .{ options.parent, name.ptr, options.init_size, options.min_size, options.max_size },
    );
    return MemoryContextAllocator.init(ctx, .{
        .flags = options.flags,
    });
}

/// Create a temporary AllocSet based memory context and update the CurrentMemoryContext to be
/// the new context.
/// Use `deinit` to restore the previous memory context.
pub fn createTempAllocSet(comptime name: [:0]const u8, options: AllocSetOptions) !TempMemoryContext {
    return TempMemoryContext.init(try createAllocSetContext(name, options));
}

const SlabContextOptions = struct {
    parent: c.MemoryContext = null,
    block_size: c.Size = @intCast(c.SLAB_DEFAULT_BLOCK_SIZE),
    chunk_size: c.Size,

    flags: c_int = MemoryContextAllocator.DEFAULT_FLAGS,
};

pub fn createSlabContext(comptime name: [:0]const u8, options: SlabContextOptions) !MemoryContextAllocator {
    const ctx: c.MemoryContext = try err.wrap(
        c.SlabContextCreateInternal,
        .{ options.parent, name.ptr, options.block_size, options.chunk_size },
    );
    return MemoryContextAllocator.init(ctx, .{
        .flags = options.flags,
    });
}

pub fn createTempSlab(comptime name: [:0]const u8, options: SlabContextOptions) !TempMemoryContext {
    return TempMemoryContext.init(try createSlabContext(name, options));
}

pub fn createGenerationContext(comptime name: [:0]const u8, options: AllocSetOptions) !MemoryContextAllocator {
    const ctx: c.MemoryContext = try err.wrap(
        c.GenerationContextCreateInternal,
        .{ options.parent, name.ptr, options.init_size, options.min_size, options.max_size },
    );
    return MemoryContextAllocator.init(ctx, .{
        .flags = options.flags,
    });
}

pub fn createTempGeneration(comptime name: [:0]const u8, options: AllocSetOptions) !TempMemoryContext {
    return TempMemoryContext.init(try createGenerationContext(name, options));
}

pub const TempMemoryContext = struct {
    current: MemoryContextAllocator,
    old: c.MemoryContext,

    const Self = @This();

    fn init(a: MemoryContextAllocator) Self {
        var self: Self = undefined;
        self.switchTo(a);
        return self;
    }

    pub fn deinit(self: *Self) void {
        _ = c.MemoryContextSwitchTo(self.old);
        self.current.deinit();
    }

    fn switchTo(self: *Self, ctx: MemoryContextAllocator) void {
        self.current = ctx;
        self.old = c.MemoryContextSwitchTo(ctx.ctx);
    }

    pub fn allocator(self: *Self) std.mem.Allocator {
        return self.current.allocator();
    }

    pub fn reset(self: *Self) void {
        self.current.reset();
    }

    pub fn registerResetCallback(self: *Self, cb: *c.MemoryContextCallback) void {
        self.current.registerResetCallback(cb);
    }

    pub fn registerAllocResetCallback(self: *Self, data: ?*anyopaque, f: c.MemoryContextCallbackFunction) !void {
        try self.current.registerAllocResetCallback(data, f);
    }

    pub fn context(self: *Self) c.MemoryContext {
        return self.current.ctx;
    }
};

/// Allocator that uses a Postgres memory context.
pub const MemoryContextAllocator = struct {
    // `MemoryContext` already is a pointer type.
    // We only capture the pointer to make sure that all allocation will happen on the chosen memory context.
    ctx: c.MemoryContext,
    flags: c_int,

    const Self = @This();

    const Options = struct {
        flags: c_int = DEFAULT_FLAGS,
    };

    const DEFAULT_FLAGS: c_int = c.MCXT_ALLOC_NO_OOM;

    pub fn init(ctx: c.MemoryContext, opts: Options) Self {
        var self: Self = undefined;
        self.setContext(ctx, opts);
        return self;
    }

    /// Delete the underlying memory context. Only use this function if you
    /// have created a temporary memory context yourself.
    pub fn deinit(self: *Self) void {
        c.MemoryContextDelete(self.ctx);
        self.ctx = null;
    }

    /// init the allocator with the given context.
    /// The context given MUST NOT be null.
    pub fn setContext(self: *Self, ctx: *c.struct_MemoryContextData, opts: Options) void {
        std.debug.assert(ctx != null);
        self.* = .{ .ctx = ctx, .flags = opts.flags };
    }

    pub fn allocated(self: *Self, recurse: bool) usize {
        return c.MemoryContextMemAllocated(self.ctx, recurse);
    }

    pub fn reset(self: *Self) void {
        c.MemoryContextReset(self.ctx);
    }

    pub fn context(self: *Self) c.MemoryContext {
        return self.ctx;
    }

    pub fn registerResetCallback(self: *Self, cb: *c.MemoryContextCallback) void {
        c.MemoryContextRegisterResetCallback(self.ctx, cb);
    }

    pub fn registerAllocResetCallback(self: *Self, data: ?*anyopaque, f: c.MemoryContextCallbackFunction) !void {
        const cb = try self.allocator().create(c.MemoryContextCallback);
        cb.* = .{ .func = f, .arg = data };
        self.registerResetCallback(cb);
    }

    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &Self.vtable,
        };
    }

    const vtable = std.mem.Allocator.VTable{
        .alloc = context_alloc,
        .free = pg_free, // pg_free ignores the pointer.
        .resize = pg_resize, // pg_resize ignores the pointer.
    };

    fn context_alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *MemoryContextAllocator = @ptrCast(@alignCast(ctx));
        const memctx = self.ctx;
        const ptr = c.MemoryContextAllocAligned(memctx, len, ptr_align, self.flags);
        return @ptrCast(ptr);
    }
};

pub const TestSuite_Mem = struct {
    pub fn testCurrentContextAllocator() !void {
        const allocator = PGCurrentContextAllocator;
        var buf = try allocator.alloc(u8, 10);
        defer allocator.free(buf);

        std.testing.expect(buf.len == 10);

        buf = allocator.realloc(buf, 20);
        std.testing.expect(buf.len == 20);
    }

    pub fn testAPI_GetErrorContext() !void {
        // Just test that we can get the error context.
        var allocator = getErrorContext();
        allocator = getErrorContextThrowOOM();
    }

    pub fn testAPI_createAllocSetContext() !void {
        var memctx = try createAllocSetContext("testAllocSetContext", .{});
        memctx.deinit();
    }

    pub fn testAPI_createTempAllocSet() !void {
        const old_current = c.CurrentMemoryContext;

        var temp = try createTempAllocSet("testTempAllocSet", .{});
        errdefer temp.deinit();

        try std.testing.expect(c.CurrentMemoryContext == temp.context());

        temp.deinit();
        try std.testing.expect(c.CurrentMemoryContext == old_current);
    }

    pub fn testAPI_creaetSlabContext() !void {
        var memctx = try createSlabContext("testSlabContext", .{});
        memctx.deinit();
    }

    pub fn testAPI_createTempSlabContext() !void {
        const old_current = c.CurrentMemoryContext;

        var temp = try createTempSlab("testTempSlab", .{});
        errdefer temp.deinit();

        try std.testing.expect(c.CurrentMemoryContext == temp.context());

        temp.deinit();
        try std.testing.expect(c.CurrentMemoryContext == old_current);
    }

    pub fn testAPI_createGenerationContext() !void {
        var memctx = try createGenerationContext("testGenerationContext", .{});
        memctx.deinit();
    }

    pub fn testAPI_createTempGenerationContext() !void {
        const old_current = c.CurrentMemoryContext;

        var temp = try createTempGeneration("testTempGeneration", .{});
        errdefer temp.deinit();

        try std.testing.expect(c.CurrentMemoryContext == temp.context());

        temp.deinit();
        try std.testing.expect(c.CurrentMemoryContext == old_current);
    }

    pub fn testMemoryContext_reset() !void {
        var memctx = try createAllocSetContext("testReset", .{});
        defer memctx.deinit();

        const buf = try memctx.alloc(u8, 10);
        _ = buf;

        const TestCB = struct {
            fn callback(data: ?*anyopaque) callconv(.C) void {
                const count_ptr: *usize = @ptrCast(@alignCast(data));
                count_ptr.* += 1;
            }
        };

        var count: usize = 0;
        memctx.registerAllocResetCallback(&count, &TestCB.callback);

        memctx.reset();
        try std.testing.expectEqual(0, memctx.allocated(false));
        try std.testing.expectEqual(1, count);
    }

    pub fn testMemoryContext_allocator() !void {
        var memctx = try createAllocSetContext("testAllocator", .{});
        defer memctx.deinit();

        const allocator = memctx.allocator();
        var buf = try allocator.alloc(u8, 10);
        defer allocator.free(buf);

        std.testing.expect(buf.len == 10);

        buf = allocator.realloc(buf, 20);
        std.testing.expect(buf.len == 20);
    }
};
