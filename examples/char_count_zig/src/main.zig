const std = @import("std");
const pgzx = @import("pgzx");
const elog = pgzx.elog;

comptime {
    pgzx.PG_MODULE_MAGIC();

    pgzx.PG_FUNCTION_V1("char_count_zig", char_count_zig);
}

fn char_count_zig(input_text: []const u8, target_char: []const u8) !u32 {
    if (target_char.len > 1) {
        return elog.Error(@src(), "Target char is more than one byte", .{});
    }

    elog.Info(@src(), "input_text: {s}\n", .{input_text});
    elog.Info(@src(), "target_char: {s}\n", .{target_char});
    elog.Info(@src(), "Target char len: {}\n", .{target_char.len});

    var count: u32 = 0;
    for (input_text) |char| {
        if (char == target_char[0]) {
            count += 1;
        }
    }
    return count;
}

// TODO:
// how can we compile these into the lib and run them from within postgres?
test "char_count_zig happy path" {
    const input_text = "Hello World";
    const target_char = "l";
    const expected_count: u32 = 3;
    const actual_count = try char_count_zig(input_text, target_char);
    try std.testing.expectEqual(expected_count, actual_count);
}
