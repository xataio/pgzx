const std = @import("std");
const pgzx = @import("pgzx");

comptime {
    pgzx.PG_MODULE_MAGIC();

    pgzx.PG_FUNCTION_V1("char_count_zig", char_count_zig);
}

fn char_count_zig(input_text: []const u8, target_char: []const u8) !u32 {
    if (target_char.len > 1) {
        return pgzx.elog.Error(@src(), "Target char is more than one byte", .{});
    }

    pgzx.elog.Info(@src(), "input_text: {s}\n", .{input_text});
    pgzx.elog.Info(@src(), "target_char: {s}\n", .{target_char});
    pgzx.elog.Info(@src(), "Target char len: {}\n", .{target_char.len});

    var count: u32 = 0;
    for (input_text) |char| {
        if (char == target_char[0]) {
            count += 1;
        }
    }
    return count;
}

const Testsuite1 = struct {
    pub fn testHappyPath() !void {
        const input_text = "Hello World";
        const target_char = "l";
        const expected_count: u32 = 3;
        const actual_count = try char_count_zig(input_text, target_char);
        try std.testing.expectEqual(expected_count, actual_count);
    }
};

const Testsuite2 = struct {
    pub fn testMoreThanOneByteError() !void {
        const input_text = "Hello World";
        const target_char = "lo";
        _ = char_count_zig(input_text, target_char) catch |err| {
            try std.testing.expectEqual(error.PGErrorStack, err);
            // TODO: how do we check the error message?
            return;
        };
        try std.testing.expect(false);
    }
};

comptime {
    pgzx.testing.registerTests(
        @import("build_options").testfn,
        .{ Testsuite1, Testsuite2 },
    );
}
