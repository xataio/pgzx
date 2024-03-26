const std = @import("std");

const c = @import("c.zig");
const err = @import("err.zig");
const mem = @import("mem.zig");
const meta = @import("meta.zig");
const varatt = @import("varatt.zig");

pub fn Conv(comptime T: type, comptime from: anytype, comptime to: anytype) type {
    return struct {
        pub const Type = T;

        pub fn fromNullableDatum(d: c.NullableDatum) !Type {
            if (d.isnull) {
                return err.PGError.UnexpectedNullValue;
            }
            return try from(d.value);
        }

        pub fn toNullableDatum(v: Type) !c.NullableDatum {
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

        pub fn fromNullableDatum(d: c.NullableDatum) !T {
            if (d.isnull) {
                return err.PGError.UnexpectedNullValue;
            }
            return from(d.value);
        }

        pub fn toNullableDatum(v: T) !c.NullableDatum {
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

        pub fn fromNullableDatum(d: c.NullableDatum) !Type {
            if (d.isnull) {
                return null;
            }
            return try C.fromNullableDatum(d);
        }

        pub fn toNullableDatum(v: Type) !c.NullableDatum {
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
    .{ c.Datum, PGDatum },
    .{ c.FunctionCallInfo, PGFunctionCallInfo },
    .{ c.NullableDatum, PGNullableDatum },
    .{ c.SortSupport, PGSortSupport },
    .{ c.StringInfo, PGStringInfo },
};

pub fn fromNullableDatum(comptime T: type, d: c.NullableDatum) !T {
    return findConv(T).fromNullableDatum(d);
}

pub fn fromDatum(comptime T: type, d: c.Datum, is_null: bool) !T {
    return findConv(T).fromNullableDatum(.{ .value = d, .isnull = is_null });
}

pub fn toNullableDatum(v: anytype) !c.NullableDatum {
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
    // fromDatum: fn(d: c.Datum) !Type
    // toDatum: fn(v: Type) !c.Datum

    if (@typeInfo(T) != .Struct) {
        return false;
    }

    // TODO: improve checks
    return @hasDecl(T, "Type") and @hasDecl(T, "fromNullableDatum") and @hasDecl(T, "toNullableDatum");
}

pub const Void = ConvNoFail(void, makeID(c.Datum), toVoid);
pub const Bool = ConvNoFail(bool, c.DatumGetBool, c.BoolGetDatum);
pub const Int8 = ConvNoFail(i8, datumGetInt8, c.Int8GetDatum);
pub const Int16 = ConvNoFail(i16, c.DatumGetInt16, c.Int16GetDatum);
pub const Int32 = ConvNoFail(i32, c.DatumGetInt32, c.Int32GetDatum);
pub const Int64 = ConvNoFail(i64, c.DatumGetInt64, c.Int64GetDatum);
pub const UInt8 = ConvNoFail(u8, c.DatumGetUInt8, c.UInt8GetDatum);
pub const UInt16 = ConvNoFail(u16, c.DatumGetUInt16, c.UInt16GetDatum);
pub const UInt32 = ConvNoFail(u32, c.DatumGetUInt32, c.UInt32GetDatum);
pub const UInt64 = ConvNoFail(u64, c.DatumGetUInt64, c.UInt64GetDatum);
pub const Float32 = ConvNoFail(f32, c.DatumGetFloat4, c.Float4GetDatum);
pub const Float64 = ConvNoFail(f64, c.DatumGetFloat8, c.Float8GetDatum);

pub const SliceU8 = Conv([]const u8, getDatumTextSlice, sliceToDatumText);
pub const SliceU8Z = Conv([:0]const u8, getDatumTextSliceZ, sliceToDatumText);

pub const PGFunctionCallInfo = ConvID(c.FunctionCallInfo);
pub const PGSortSupport = ConvID(c.SortSupport);
pub const PGStringInfo = Conv(c.StringInfo, datumGetStringInfo, c.PointerGetDatum);

pub const PGDatum = ConvID(c.Datum);
const PGNullableDatum = struct {
    pub const Type = c.NullableDatum;

    pub fn fromNullableDatum(d: c.NullableDatum) !Type {
        return d;
    }

    pub fn toNullableDatum(v: Type) !c.NullableDatum {
        return v;
    }
};

// TODO: conversion decorator for array types

// TODO: conversion decorator for jsonb decoding/encoding types

fn ConvID(comptime T: type) type {
    const idFn = makeID(T);

    return ConvNoFail(T, idFn, idFn);
}

fn makeID(comptime T: type) fn (T) T {
    return struct {
        fn id(t: T) T {
            return t;
        }
    }.id;
}

fn datumGetStringInfo(datum: c.Datum) !c.StringInfo {
    return datumGetPointer(c.StringInfo, datum);
}

inline fn datumGetPointer(comptime T: type, datum: c.Datum) T {
    return @ptrCast(@alignCast(c.DatumGetPointer(datum)));
}

fn toVoid(d: void) c.Datum {
    _ = d;
    return 0;
}

fn datumGetInt8(d: c.Datum) i8 {
    return @as(i8, @bitCast(@as(i8, @truncate(d))));
}

/// Convert a datum to a TEXT slice. This function detoast the datum if necessary.
/// All allocations will be performed in the Current Memory Context.
pub fn getDatumTextSlice(datum: c.Datum) ![]const u8 {
    return getDatumTextSliceZ(datum);
}

/// Convert a datum to a TEXT slice. This function detoast the datum if necessary.
/// All allocations will be performed in the Current Memory Context.
///
pub fn getDatumTextSliceZ(datum: c.Datum) ![:0]const u8 {
    const ptr = c.DatumGetTextPP(datum);

    const unpacked = try err.wrap(c.pg_detoast_datum_packed, .{ptr});
    const len = varatt.VARSIZE_ANY_EXHDR(unpacked);
    var buffer = try mem.PGCurrentContextAllocator.alloc(u8, len + 1);
    std.mem.copyForwards(u8, buffer, varatt.VARDATA_ANY(unpacked)[0..len]);
    buffer[len] = 0;
    if (unpacked != ptr) {
        c.pfree(unpacked);
    }
    return buffer[0..len :0];
}

pub inline fn sliceToDatumText(slice: []const u8) !c.Datum {
    const text = c.cstring_to_text_with_len(slice.ptr, @intCast(slice.len));
    return c.PointerGetDatum(text);
}

pub inline fn sliceToDatumTextZ(slice: [:0]const u8) !c.Datum {
    return sliceToDatumText(slice);
}
