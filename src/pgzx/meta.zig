pub inline fn isPointer(comptime T: type) bool {
    return @typeInfo(T) == .pointer and !isSlice(T);
}

pub inline fn isCPointer(comptime T: type) bool {
    @compileLog("isCPointer: {}", T, @typeInfo(T));
    return @typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .c;
}

pub inline fn isSlice(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |p| p.size == .slice,
        else => false,
    };
}

pub inline fn maybeSliceElemType(comptime T: type) ?type {
    if (!isSlice(T)) return null;
    return @typeInfo(T).pointer.child;
}

pub inline fn sliceElemType(comptime T: type) type {
    return maybeSliceElemType(T) orelse @compileError("Expected a slice type");
}

pub inline fn maybePointerElemType(comptime T: type) ?type {
    return switch (@typeInfo(T)) {
        .pointer => |p| p.child,
        else => null,
    };
}

pub inline fn pointerElemType(comptime T: type) type {
    return maybePointerElemType(T) orelse @compileError("Expected a pointer type");
}

pub inline fn hasSentinal(comptime T: type) bool {
    return isSlice(T) and @typeInfo(T).pointer.sentinel() != null;
}

pub inline fn isStringLike(comptime T: type) bool {
    return isSlice(T) and sliceElemType(T) == u8;
}

pub inline fn isStringLikeZ(comptime T: type) bool {
    return isStringLike(T) and hasSentinal(T);
}

pub inline fn isPrimitive(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .bool, .int, .float => true,
        else => false,
    };
}

pub inline fn getFnType(comptime T: type, name: []const u8) ?type {
    switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => {},
        else => return null,
    }
    if (!@hasDecl(T, name)) {
        return null;
    }

    const maybeFn = @TypeOf(@field(T, name));
    return if (@typeInfo(maybeFn) == .@"fn")
        maybeFn
    else
        null;
}

pub inline fn getMethodType(comptime T: type, name: []const u8) ?type {
    return switch (@typeInfo(T)) {
        .pointer => |p| switch (p.size) {
            .one => getFnType(p.child, name),
            else => null,
        },
        else => getFnType(T, name),
    };
}

pub inline fn fnReturnType(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .@"fn" => |f| f.return_type.?,
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
