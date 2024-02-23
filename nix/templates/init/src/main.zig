const std = @import("std");
const pgzx = @import("pgzx");

comptime {
    pgzx.PG_MODULE_MAGIC();

    pgzx.PG_FUNCTION_V1("hello", hello);
}

fn hello() ![:0]const u8 {
    return "Hello, world!";
}
