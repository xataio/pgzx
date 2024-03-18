pub inline fn isSlice(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .Pointer => |p| p.size == .Slice,
        else => false,
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

pub inline fn fnReturnType(comptime T: type, comptime fnName: []const u8) type {
    return switch (@typeInfo(@field(T, fnName))) {
        .Fn => |f| f.return_type.?,
        else => @compileError("Expected a function type"),
    };
}
