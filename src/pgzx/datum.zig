const std = @import("std");

const pg = @import("pgzx_pgsys");

const err = @import("err.zig");
const mem = @import("mem.zig");
const meta = @import("meta.zig");
const varatt = @import("varatt.zig");

pub fn Conv(comptime T: type, comptime from: anytype, comptime to: anytype) type {
    return struct {
        pub const Type = T;
        pub fn fromNullableDatum(d: pg.NullableDatum) !Type {
            if (d.isnull) {
                return err.PGError.UnexpectedNullValue;
            }
            return try from(d.value);
        }
        pub fn toNullableDatum(v: Type) !pg.NullableDatum {
            return .{
                .value = try to(v),
                .isnull = false,
            };
        }
    };
}

pub fn ConvNoFail(comptime T: type, comptime from: anytype, comptime to: anytype) type {
    return struct {
        pub const Type = T;
        pub fn fromNullableDatum(d: pg.NullableDatum) !T {
            if (d.isnull) {
                return err.PGError.UnexpectedNullValue;
            }
            return from(d.value);
        }
        pub fn toNullableDatum(v: T) !pg.NullableDatum {
            return .{
                .value = to(v),
                .isnull = false,
            };
        }
    };
}

/// Conversion decorator for optional types.
pub fn OptConv(comptime C: anytype) type {
    return struct {
        pub const Type = ?C.Type;
        pub fn fromNullableDatum(d: pg.NullableDatum) !Type {
            if (d.isnull) {
                return null;
            }
            return try C.fromNullableDatum(d);
        }
        pub fn toNullableDatum(v: Type) !pg.NullableDatum {
            if (v) |value| {
                return try C.toNullableDatum(value);
            } else {
                return .{
                    .value = 0,
                    .isnull = true,
                };
            }
        }
    };
}

/// Map concrete type to their converters.
/// This allows us find to return pre-defined converters besides relying on
/// reflection only.
var directMappings = .{
    .{ pg.Datum, PGDatum },
    .{ pg.NullableDatum, PGNullableDatum },
};

pub fn fromNullableDatum(comptime T: type, d: pg.NullableDatum) !T {
    return findConv(T).fromNullableDatum(d);
}

pub fn fromDatum(comptime T: type, d: pg.Datum, is_null: bool) !T {
    return findConv(T).fromNullableDatum(.{ .value = d, .isnull = is_null });
}

pub fn toNullableDatum(v: anytype) !pg.NullableDatum {
    return findConv(@TypeOf(v)).toNullableDatum(v);
}

pub fn findConv(comptime T: type) type {
    if (isConv(T)) { // is T already a converter?
        return T;
    }
    comptime for (directMappings) |e| {
        if (e[0] == T) {
            return e[1];
        }
    };

    // TODO:
    // allow types to implement conversion functions directly
    // in that case we will return the original type by wrapping it in
    // Conv

    return switch (@typeInfo(T)) {
        .Void => Void,
        .Bool => Bool,
        .Int => |i| switch (i.signedness) {
            .signed => switch (i.bits) {
                8 => Int8,
                16 => Int16,
                32 => Int32,
                64 => Int64,
                else => @compileError("unsupported int type"),
            },
            .unsigned => switch (i.bits) {
                8 => UInt8,
                16 => UInt16,
                32 => UInt32,
                64 => UInt64,
                else => @compileError("unsupported unsigned int type"),
            },
        },
        .Float => |f| switch (f.bits) {
            32 => Float32,
            64 => Float64,
            else => @compileError("unsupported float type"),
        },
        .Optional => |opt| OptConv(findConv(opt.child)),
        .Array => @compileLog("fixed size arrays not supported"),
        .Pointer => blk: {
            if (!meta.isStringLike(T)) {
                @compileLog("type:", T);
                @compileError("unsupported ptr type");
            }
            break :blk if (meta.hasSentinal(T)) SliceU8Z else SliceU8;
        },
        else => {
            @compileLog("type:", T);
            @compileError("type not supported");
        },
    };
}

inline fn isConv(comptime T: type) bool {
    // we require T to be a struct with the following fields:
    // Type: type
    // fromDatum: fn(d: pg.Datum) !Type
    // toDatum: fn(v: Type) !pg.Datum

    if (@typeInfo(T) != .Struct) {
        return false;
    }

    // TODO: improve checks
    return @hasDecl(T, "Type") and @hasDecl(T, "fromNullableDatum") and @hasDecl(T, "toNullableDatum");
}

pub const Void = ConvNoFail(void, idDatum, toVoid);
pub const Bool = ConvNoFail(bool, pg.DatumGetBool, pg.BoolGetDatum);
pub const Int8 = ConvNoFail(i8, datumGetInt8, pg.Int8GetDatum);
pub const Int16 = ConvNoFail(i16, pg.DatumGetInt16, pg.Int16GetDatum);
pub const Int32 = ConvNoFail(i32, pg.DatumGetInt32, pg.Int32GetDatum);
pub const Int64 = ConvNoFail(i64, pg.DatumGetInt64, pg.Int64GetDatum);
pub const UInt8 = ConvNoFail(u8, pg.DatumGetUInt8, pg.UInt8GetDatum);
pub const UInt16 = ConvNoFail(u16, pg.DatumGetUInt16, pg.UInt16GetDatum);
pub const UInt32 = ConvNoFail(u32, pg.DatumGetUInt32, pg.UInt32GetDatum);
pub const UInt64 = ConvNoFail(u64, pg.DatumGetUInt64, pg.UInt64GetDatum);
pub const Float32 = ConvNoFail(f32, pg.DatumGetFloat4, pg.Float4GetDatum);
pub const Float64 = ConvNoFail(f64, pg.DatumGetFloat8, pg.Float8GetDatum);

pub const SliceU8 = Conv([]const u8, getDatumTextSlice, sliceToDatumText);
pub const SliceU8Z = Conv([:0]const u8, getDatumTextSliceZ, sliceToDatumTextZ);

pub const PGDatum = ConvNoFail(pg.Datum, idDatum, idDatum);
const PGNullableDatum = struct {
    pub const Type = pg.NullableDatum;
    pub fn fromNullableDatum(d: pg.NullableDatum) !Type {
        return d;
    }
    pub fn toNullableDatum(v: Type) !pg.NullableDatum {
        return v;
    }
};

// TODO: conversion decorator for array types

// TODO: conversion decorator for jsonb decoding/encoding types

fn idDatum(d: pg.Datum) pg.Datum {
    return d;
}

fn toVoid(d: void) pg.Datum {
    _ = d;
    return 0;
}

fn datumGetInt8(d: pg.Datum) i8 {
    return @as(i8, @bitCast(@as(i8, @truncate(d))));
}

/// Convert a datum to a TEXT slice. This function detoast the datum if necessary.
/// All allocations will be performed in the Current Memory Context.
pub fn getDatumTextSlice(datum: pg.Datum) ![]const u8 {
    return getDatumTextSliceZ(datum);
}

/// Convert a datum to a TEXT slice. This function detoast the datum if necessary.
/// All allocations will be performed in the Current Memory Context.
///
pub fn getDatumTextSliceZ(datum: pg.Datum) ![:0]const u8 {
    const ptr = pg.DatumGetTextPP(datum);

    const unpacked = try err.wrap(pg.pg_detoast_datum_packed, .{ptr});
    const len = varatt.VARSIZE_ANY_EXHDR(unpacked);
    var buffer = try mem.PGCurrentContextAllocator.alloc(u8, len + 1);
    std.mem.copyForwards(u8, buffer, varatt.VARDATA_ANY(unpacked)[0..len]);
    buffer[len] = 0;
    if (unpacked != ptr) {
        pg.pfree(unpacked);
    }
    return buffer[0..len :0];
}

pub inline fn sliceToDatumText(slice: []const u8) !pg.Datum {
    const text = pg.cstring_to_text_with_len(slice.ptr, @intCast(slice.len));
    return pg.PointerGetDatum(text);
}

pub inline fn sliceToDatumTextZ(slice: [:0]const u8) !pg.Datum {
    return sliceToDatumText(slice);
}
