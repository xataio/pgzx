const std = @import("std");
const builtin = @import("builtin");
const BORDER = "=" ** 80;

const Status = enum {
    pass,
    fail,
    skip,
    text,
};

fn getenvOwned(alloc: std.mem.Allocator, key: []const u8) ?[]u8 {
    const v = std.process.getEnvVarOwned(alloc, key) catch |err| {
        if (err == error.EnvironmentVariableNotFound) {
            return null;
        }
        std.log.warn("failed to get env var {s} due to err {}", .{ key, err });
        return null;
    };
    return v;
}

pub fn main() !void {
    std.log.warn("HERE\n", .{});
}

const Printer = struct {
    out: std.fs.File.Writer,

    fn init() Printer {
        return .{
            .out = std.io.getStdErr().writer(),
        };
    }

    fn fmt(self: Printer, comptime format: []const u8, args: anytype) void {
        std.fmt.format(self.out, format, args) catch unreachable;
    }

    fn status(self: Printer, s: Status, comptime format: []const u8, args: anytype) void {
        const color = switch (s) {
            .pass => "\x1b[32m",
            .fail => "\x1b[31m",
            .skip => "\x1b[33m",
            else => "",
        };
        const out = self.out;
        out.writeAll(color) catch @panic("writeAll failed?!");
        std.fmt.format(out, format, args) catch @panic("std.fmt.format failed?!");
        self.fmt("\x1b[0m", .{});
    }
};
