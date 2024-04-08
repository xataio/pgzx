const std = @import("std");

const c = @import("../c.zig");
const meta = @import("../meta.zig");

pub const Error = error{
    InvalidBool,
};

pub fn find(comptime T: type) type {
    if (isConv(T)) {
        return T;
    }

    return switch (@typeInfo(T)) {
        .Bool => boolconv,
        .Int => |i| switch (i.signedness) {
            .signed => switch (i.bits) {
                8 => i8conv,
                16 => i16conv,
                32 => i32conv,
                64 => i64conv,
                else => {
                    @compileLog("type:", T);
                    @compileError("unsupported int type");
                },
            },
            .unsigned => switch (i.bits) {
                8 => u8conv,
                16 => u16conv,
                32 => u32conv,
                else => {
                    @compileLog("type:", T);
                    @compileError("unsupported unsigned int type");
                },
            },
        },
        .Float => |f| switch (f.bits) {
            32 => f32conv,
            64 => f64conv,
            else => {
                @compileLog("type:", T);
                @compileError("unsupported float type");
            },
        },
        .Optional => |opt| optconv(find(opt.child)),
        .Array => @compileLog("fixed size arrays not supported"),
        .Pointer => blk: {
            if (!meta.isStringLike(T)) {
                @compileLog("type:", T);
                @compileError("unsupported ptr type");
            }
            break :blk if (meta.hasSentinal(T)) textzconv else textconv;
        },
        else => {
            @compileLog("type:", T);
            @compileError("type not supported");
        },
    };
}

fn isConv(comptime T: type) bool {
    if (@typeInfo(T) != .Struct) {
        return false;
    }

    return @hasDecl(T, "Type") and @hasDecl(T, "OID") and @hasDecl(T, "write") and @hasDecl(T, "parse");
}

fn optconv(comptime C: type) type {
    return struct {
        pub const OID = C.OID;
        pub const Type = ?C.Type;

        pub fn write(writer: anytype, value: Type) !void {
            if (value) |v| {
                try C.write(writer, v);
            }
        }

        pub fn parse(buf: [:0]const u8) !Type {
            if (buf.len == 0) {
                return null;
            }
            return try C.parse(buf);
        }
    };
}

const boolconv = struct {
    pub const OID = c.BOOLOID;
    pub const Type = bool;

    pub fn write(writer: anytype, value: bool) !void {
        if (value) {
            _ = try writer.writeByte('t');
        } else {
            _ = try writer.writeByte('f');
        }
        try writer.writeByte(0);
    }

    pub fn parse(buf: [:0]const u8) !bool {
        if (buf.len != 1) {
            return Error.InvalidBool;
        }
        switch (buf[0]) {
            't' => return true,
            'f' => return false,
            _ => return Error.InvalidBool,
        }
    }
};

const i8conv = intconv(i8, c.INT2OID);
const i16conv = intconv(i16, c.INT2OID);
const i32conv = intconv(i32, c.INT4OID);
const i64conv = intconv(i64, c.INT8OID);
const u8conv = intconv(u8, c.INT2OID);
const u16conv = intconv(u16, c.INT4OID);
const u32conv = intconv(u32, c.INT8OID);
fn intconv(comptime T: type, comptime oid: c.Oid) type {
    return struct {
        pub const OID = oid;
        pub const Type = T;

        pub fn write(writer: anytype, value: T) !void {
            try std.fmt.format(writer, "{d}", .{value});
            try writer.writeByte(0);
        }

        pub fn parse(buf: [:0]const u8) !T {
            var result: T = undefined;
            try std.fmt.parseInt(buf, &result, 10);
            return result;
        }
    };
}

const f32conv = floatconv(f32, c.FLOAT4OID);
const f64conv = floatconv(f64, c.FLOAT8OID);
fn floatconv(comptime T: type, comptime oid: c.Oid) type {
    return struct {
        pub const OID = oid;
        pub const Type = T;

        pub fn write(writer: anytype, value: T) !void {
            try std.fmt.format(writer, "{f}", .{value});
            try writer.writeByte(0);
        }

        pub fn parse(buf: [:0]const u8) !T {
            var result: T = undefined;
            try std.fmt.parseFloat(buf, &result);
            return result;
        }
    };
}

const textconv = struct {
    pub const OID = c.TEXTOID;
    pub const Type = []const u8;

    pub fn write(writer: anytype, value: []const u8) !void {
        _ = try writer.write(value);
        try writer.writeByte(0);
    }

    pub fn parse(buf: [:0]const u8) ![]const u8 {
        return buf;
    }
};

const textzconv = struct {
    pub const OID = c.TEXTOID;
    pub const Type = [:0]const u8;

    pub fn write(writer: anytype, value: [:0]const u8) !void {
        _ = try writer.write(value);
    }

    pub fn parse(buf: [:0]const u8) ![:0]const u8 {
        return buf;
    }
};
