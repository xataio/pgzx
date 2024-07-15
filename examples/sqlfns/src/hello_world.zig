const std = @import("std");
const pgzx = @import("pgzx");

pub fn hello_world_file(name: ?[:0]const u8) ![:0]const u8 {
    return if (name) |n|
        try std.fmt.allocPrintZ(pgzx.mem.PGCurrentContextAllocator, "Hello, {s}!", .{n})
    else
        "Hello World";
}
