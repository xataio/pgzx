const std = @import("std");
const mem = @import("mem.zig");

pub const CString = [:0]const u8;
pub const CStringPtr = [*c]const u8;

/// Return a formatted string or error.
///
/// The string will be allocated on the current PostgreSQL memory context.
pub fn format(
    comptime fmt: []const u8,
    args: anytype,
) !CString {
    return try std.fmt.allocPrintZ(mem.PGCurrentContextAllocator, fmt, args);
}

/// Return a formatted string or error.
/// The memory for the message is allocated from the given allocator (or
/// mem.PGCurrentContextAllocator if null).
pub fn formatMemCtx(
    alloc: ?*mem.MemoryContextAllocator,
    comptime fmt: []const u8,
    args: anytype,
) !CString {
    const use_alloc = if (alloc) |a| a.allocator() else mem.PGCurrentContextAllocator;
    return try std.fmt.allocPrintZ(use_alloc, fmt, args);
}
