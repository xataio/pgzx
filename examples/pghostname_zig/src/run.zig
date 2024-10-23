const std = @import("std");

pub fn pghostname_zig() ![]const u8 {
    var buffer: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname = std.posix.gethostname(&buffer) catch |err| switch (err) {
        error.PermissionDenied => {
            return "unknown";
        },
        error.Unexpected => {
            return "unknown";
        },
    };
    std.debug.print("buffer: {s}", .{buffer});
    return hostname;
}

pub fn main() void {
    const hostname = try pghostname_zig();
    std.debug.print("hostname: {s}\n", .{hostname});
}
