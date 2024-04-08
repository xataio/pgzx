pub inline fn isSlice(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .Pointer => |p| p.size == .Slice,
        else => false,
    };
}

pub inline fn sliceElemType(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .Pointer => |p| {
            if (p.size != .Slice) {
                @compileError("Expected a slice type");
            }
            return p.child;
        },
        else => @compileError("Expected a slice type"),
    };
}

pub inline fn hasSentinal(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .Pointer => |p| p.size == .Slice and p.sentinel != null,
        else => false,
    };
}

pub inline fn isStringLike(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .Pointer => |p| p.size == .Slice and p.child == u8,
        else => false,
    };
}

pub inline fn isStringLikeZ(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .Pointer => |p| p.size == .Slice and p.child == u8 and p.sentinel != null,
        else => false,
    };
}

pub inline fn isPrimitive(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .Bool, .Int, .Float => true,
        else => false,
    };
}

pub inline fn getFnType(comptime T: type, name: []const u8) ?type {
    switch (@typeInfo(T)) {
        .Struct, .Union, .Enum, .Opaque => {},
        else => return null,
    }
    if (!@hasDecl(T, name)) {
        return null;
    }

    const maybeFn = @TypeOf(@field(T, name));
    return if (@typeInfo(maybeFn) == .Fn)
        maybeFn
    else
        null;
}

pub inline fn getMethodType(comptime T: type, name: []const u8) ?type {
    return switch (@typeInfo(T)) {
        .Pointer => |p| switch (p.size) {
            .One => getFnType(p.child, name),
            else => null,
        },
        else => getFnType(T, name),
    };
}

pub inline fn fnReturnType(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .Fn => |f| f.return_type.?,
        else => @compileError("Expected a function type"),
    };
}

pub inline fn methodReturnType(comptime T: type, name: []const u8) type {
    const maybeMethod = getMethodType(T, name);
    if (maybeMethod == null) {
        @compileError("Method not found");
    }
    return fnReturnType(maybeMethod.?);
}

pub const TestSuite_Meta = struct {
    const std = @import("std");

    pub fn testIsSlice() !void {
        try std.testing.expect(!isSlice(u8));
        try std.testing.expect(isSlice([]u8));
        try std.testing.expect(isSlice([:0]u8));
    }

    pub fn testSliceElemType() !void {
        try std.testing.expect(sliceElemType([]u8) == u8);
        try std.testing.expect(sliceElemType([:0]u8) == u8);
    }

    pub fn testHasSentinal() !void {
        try std.testing.expect(!hasSentinal(u8));
        try std.testing.expect(!hasSentinal([]u8));
        try std.testing.expect(hasSentinal([:0]u8));
    }

    pub fn testIsStringLike() !void {
        try std.testing.expect(!isStringLike(u8));
        try std.testing.expect(isStringLike([]u8));
        try std.testing.expect(isStringLike([:0]u8));
    }

    pub fn testIsStringLikeZ() !void {
        try std.testing.expect(!isStringLikeZ(u8));
        try std.testing.expect(!isStringLikeZ([]u8));
        try std.testing.expect(isStringLikeZ([:0]u8));
    }

    pub fn testIsPrimitive() !void {
        try std.testing.expect(isPrimitive(bool));
        try std.testing.expect(isPrimitive(i32));
        try std.testing.expect(isPrimitive(f32));
        try std.testing.expect(!isPrimitive([]u8));

        const myU8 = u8;
        try std.testing.expect(isPrimitive(myU8));
    }

    pub fn testGetFnType() !void {
        try std.testing.expect(getFnType(u8, "foo") == null);
        try std.testing.expect(getFnType([:0]u8, "foo") == null);
        try std.testing.expect(getFnType(struct {}, "foo") == null);

        const S = struct {
            pub fn foo() void {}
        };
        try std.testing.expect(getFnType(S, "foo") != null);
        try std.testing.expect(getFnType(S, "foo").? == @TypeOf(S.foo));

        const U = union {
            pub fn foo() void {}
        };
        try std.testing.expect(getFnType(U, "foo") != null);
        try std.testing.expect(getFnType(U, "foo").? == @TypeOf(U.foo));
    }

    pub fn testGetMethodType() !void {
        const S = struct {
            pub fn foo(self: *@This()) void {
                _ = self;
            }
        };
        try std.testing.expect(getMethodType(*S, "bar") == null);
        try std.testing.expect(getMethodType(*S, "foo") != null);
        try std.testing.expect(getMethodType(*S, "foo") == @TypeOf(S.foo));

        const U = union {
            pub fn foo(self: *@This()) void {
                _ = self;
            }
        };
        try std.testing.expect(getMethodType(*U, "foo") != null);
        try std.testing.expect(getMethodType(*U, "foo") == @TypeOf(U.foo));
    }

    pub fn testMethodReturnType() !void {
        const S = struct {
            pub fn foo(self: *@This()) u8 {
                _ = self;
            }
        };
        try std.testing.expect(methodReturnType(*S, "foo") == u8);

        const U = union {
            pub fn foo(self: *@This()) u32 {
                _ = self;
            }
        };
        try std.testing.expect(methodReturnType(*U, "foo") == u32);
    }
};
