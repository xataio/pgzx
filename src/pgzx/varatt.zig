//! varatt replaces the VA<...> macros from utils/varattr.h that Zig didn't
//! compile correctly.

const pg = @import("pgzx_pgsys");

// WARNING:
// Taken from translated C code and mostly untested.
// The zig compiler will not complain about errors if inline functions are not used.
//
// TODO:
// We do not want to expose these directly, but we must make sure that we test
// all variable conversions to make sure that code actually compiles.

pub const VARHDRSZ = pg.VARHDRSZ;
pub const VARHDRSZ_SHORT = @sizeOf(varattrib_1b);
pub const VARHDRSZ_EXTERNAL = @sizeOf(varattrib_1b_e);

pub const VARLENA_EXTSIZE_BITS = pg.VARLENA_EXTSIZE_BITS;

pub const VARTAG_EXPANDED_RO = pg.VARTAG_EXPANDED_RO;
pub const VARTAG_EXPANDED_RW = pg.VARTAG_EXPANDED_RW;
pub const VARTAG_INDIRECT = pg.VARTAG_INDIRECT;
pub const VARTAG_ONDISK = pg.VARTAG_ONDISK;

pub const SET_VARSIZE_4B = pg.SET_VARSIZE_4B;
pub const SET_VARSIZE_1B = pg.SET_VARSIZE_1B;
pub const SET_VARSIZE_4B_C = pg.SET_VARSIZE_4B_C;
pub const SET_VARTAG_1B_E = pg.SET_VARTAG_1B_E;

pub const varatt_indirect = pg.varatt_indirect;
pub const varatt_expanded = pg.varatt_expanded;
pub const varatt_external = pg.varatt_external;
pub const varattrib_1b = pg.varattrib_1b;
pub const varattrib_4b = pg.varattrib_4b;
pub const varattrib_1b_e = pg.varattrib_1b_e;

pub const VARLENA_EXTSIZE_MASK = (@as(c_uint, 1) << VARLENA_EXTSIZE_BITS) - @as(c_int, 1);

pub const @"true" = @as(c_int, 1);
pub const @"false" = @as(c_int, 0);

pub inline fn VARTAG_IS_EXPANDED(tag: anytype) @TypeOf((tag & ~@as(c_int, 1)) == VARTAG_EXPANDED_RO) {
    return (tag & ~@as(c_int, 1)) == VARTAG_EXPANDED_RO;
}

pub inline fn VARTAG_SIZE(tag: anytype) @TypeOf(if (tag == VARTAG_INDIRECT) @import("std").zig.c_translation.sizeof(varatt_indirect) else if (VARTAG_IS_EXPANDED(tag)) @import("std").zig.c_translation.sizeof(varatt_expanded) else if (tag == VARTAG_ONDISK) @import("std").zig.c_translation.sizeof(varatt_external) else blk_2: {
    break :blk_2 @as(c_int, 0);
}) {
    return if (tag == VARTAG_INDIRECT) @import("std").zig.c_translation.sizeof(varatt_indirect) else if (VARTAG_IS_EXPANDED(tag)) @import("std").zig.c_translation.sizeof(varatt_expanded) else if (tag == VARTAG_ONDISK) @import("std").zig.c_translation.sizeof(varatt_external) else blk_2: {
        break :blk_2 @as(c_int, 0);
    };
}

pub inline fn VARATT_IS_4B(PTR: anytype) @TypeOf((@import("std").zig.c_translation.cast([*c]varattrib_1b, PTR).*.va_header & @as(c_int, 0x01)) == @as(c_int, 0x00)) {
    return (@import("std").zig.c_translation.cast([*c]varattrib_1b, PTR).*.va_header & @as(c_int, 0x01)) == @as(c_int, 0x00);
}

pub inline fn VARATT_IS_4B_U(PTR: anytype) @TypeOf((@import("std").zig.c_translation.cast([*c]varattrib_1b, PTR).*.va_header & @as(c_int, 0x03)) == @as(c_int, 0x00)) {
    return (@import("std").zig.c_translation.cast([*c]varattrib_1b, PTR).*.va_header & @as(c_int, 0x03)) == @as(c_int, 0x00);
}

pub inline fn VARATT_IS_4B_C(PTR: anytype) @TypeOf((@import("std").zig.c_translation.cast([*c]varattrib_1b, PTR).*.va_header & @as(c_int, 0x03)) == @as(c_int, 0x02)) {
    return (@import("std").zig.c_translation.cast([*c]varattrib_1b, PTR).*.va_header & @as(c_int, 0x03)) == @as(c_int, 0x02);
}

pub inline fn VARATT_IS_1B(PTR: anytype) @TypeOf((@import("std").zig.c_translation.cast([*c]varattrib_1b, PTR).*.va_header & @as(c_int, 0x01)) == @as(c_int, 0x01)) {
    return (@import("std").zig.c_translation.cast([*c]varattrib_1b, PTR).*.va_header & @as(c_int, 0x01)) == @as(c_int, 0x01);
}

pub inline fn VARATT_IS_1B_E(PTR: anytype) @TypeOf(@import("std").zig.c_translation.cast([*c]varattrib_1b, PTR).*.va_header == @as(c_int, 0x01)) {
    return @import("std").zig.c_translation.cast([*c]varattrib_1b, PTR).*.va_header == @as(c_int, 0x01);
}

pub inline fn VARATT_NOT_PAD_BYTE(PTR: anytype) @TypeOf(@import("std").zig.c_translation.cast([*c]pg.uint8, PTR).* != @as(c_int, 0)) {
    return @import("std").zig.c_translation.cast([*c]pg.uint8, PTR).* != @as(c_int, 0);
}

pub inline fn VARSIZE_4B(PTR: anytype) @TypeOf((@import("std").zig.c_translation.cast([*c]varattrib_4b, PTR).*.va_4byte.va_header >> @as(pg.uint32, 2)) & @import("std").zig.c_translation.promoteIntLiteral(pg.uint32, 0x3FFFFFFF, .hex)) {
    _ = &PTR;
    return (@import("std").zig.c_translation.cast([*c]varattrib_4b, PTR).*.va_4byte.va_header >> @as(pg.uint32, 2)) & @import("std").zig.c_translation.promoteIntLiteral(pg.uint32, 0x3FFFFFFF, .hex);
}

pub inline fn VARSIZE_1B(PTR: anytype) @TypeOf((@import("std").zig.c_translation.cast([*c]varattrib_1b, PTR).*.va_header >> @as(pg.uint32, 1)) & @as(pg.uint32, 0x7F)) {
    return (@import("std").zig.c_translation.cast([*c]varattrib_1b, PTR).*.va_header >> @as(pg.uint32, 1)) & @as(pg.uint32, 0x7F);
}

pub inline fn VARTAG_1B_E(PTR: anytype) @TypeOf(@import("std").zig.c_translation.cast([*c]varattrib_1b_e, PTR).*.va_tag) {
    return @import("std").zig.c_translation.cast([*c]varattrib_1b_e, PTR).*.va_tag;
}

pub inline fn VARDATA_4B(PTR: anytype) @TypeOf(@import("std").zig.c_translation.cast([*c]varattrib_4b, PTR).*.va_4byte.va_data()) {
    return @import("std").zig.c_translation.cast([*c]varattrib_4b, PTR).*.va_4byte.va_data();
}

pub inline fn VARDATA_4B_C(PTR: anytype) @TypeOf(@import("std").zig.c_translation.cast([*c]varattrib_4b, PTR).*.va_compressed.va_data) {
    return @import("std").zig.c_translation.cast([*c]varattrib_4b, PTR).*.va_compressed.va_data;
}

pub inline fn VARDATA_1B(PTR: anytype) @TypeOf(@import("std").zig.c_translation.cast([*c]varattrib_1b, PTR).*.va_data()) {
    return @import("std").zig.c_translation.cast([*c]varattrib_1b, PTR).*.va_data();
}

pub inline fn VARDATA_1B_E(PTR: anytype) @TypeOf(@import("std").zig.c_translation.cast([*c]varattrib_1b_e, PTR).*.va_data()) {
    return @import("std").zig.c_translation.cast([*c]varattrib_1b_e, PTR).*.va_data;
}

pub const VARATT_SHORT_MAX = @as(c_int, 0x7F);

pub inline fn VARATT_CAN_MAKE_SHORT(PTR: anytype) @TypeOf((VARATT_IS_4B_U(PTR) != 0) and (((VARSIZE(PTR) - VARHDRSZ) + VARHDRSZ_SHORT) <= VARATT_SHORT_MAX)) {
    return (VARATT_IS_4B_U(PTR) != 0) and (((VARSIZE(PTR) - VARHDRSZ) + VARHDRSZ_SHORT) <= VARATT_SHORT_MAX);
}

pub inline fn VARATT_CONVERTED_SHORT_SIZE(PTR: anytype) @TypeOf((VARSIZE(PTR) - VARHDRSZ) + VARHDRSZ_SHORT) {
    return (VARSIZE(PTR) - VARHDRSZ) + VARHDRSZ_SHORT;
}

pub inline fn VARDATA(PTR: anytype) @TypeOf(VARDATA_4B(PTR)) {
    return VARDATA_4B(PTR);
}

pub inline fn VARSIZE(PTR: anytype) @TypeOf(VARSIZE_4B(PTR)) {
    return VARSIZE_4B(PTR);
}

pub inline fn VARSIZE_SHORT(PTR: anytype) @TypeOf(VARSIZE_1B(PTR)) {
    return VARSIZE_1B(PTR);
}

pub inline fn VARDATA_SHORT(PTR: anytype) @TypeOf(VARDATA_1B(PTR)) {
    return VARDATA_1B(PTR);
}

pub inline fn VARTAG_EXTERNAL(PTR: anytype) @TypeOf(VARTAG_1B_E(PTR)) {
    return VARTAG_1B_E(PTR);
}

pub inline fn VARSIZE_EXTERNAL(PTR: anytype) @TypeOf(VARHDRSZ_EXTERNAL + VARTAG_SIZE(VARTAG_EXTERNAL(PTR))) {
    return VARHDRSZ_EXTERNAL + VARTAG_SIZE(VARTAG_EXTERNAL(PTR));
}

pub inline fn VARDATA_EXTERNAL(PTR: anytype) @TypeOf(VARDATA_1B_E(PTR)) {
    return VARDATA_1B_E(PTR);
}

pub inline fn VARATT_IS_COMPRESSED(PTR: anytype) @TypeOf(VARATT_IS_4B_C(PTR)) {
    return VARATT_IS_4B_C(PTR);
}

pub inline fn VARATT_IS_EXTERNAL(PTR: anytype) @TypeOf(VARATT_IS_1B_E(PTR)) {
    return VARATT_IS_1B_E(PTR);
}

pub inline fn VARATT_IS_EXTERNAL_ONDISK(PTR: anytype) @TypeOf((VARATT_IS_EXTERNAL(PTR) != 0) and (VARTAG_EXTERNAL(PTR) == VARTAG_ONDISK)) {
    return (VARATT_IS_EXTERNAL(PTR) != 0) and (VARTAG_EXTERNAL(PTR) == VARTAG_ONDISK);
}

pub inline fn VARATT_IS_EXTERNAL_INDIRECT(PTR: anytype) @TypeOf((VARATT_IS_EXTERNAL(PTR) != 0) and (VARTAG_EXTERNAL(PTR) == VARTAG_INDIRECT)) {
    return (VARATT_IS_EXTERNAL(PTR) != 0) and (VARTAG_EXTERNAL(PTR) == VARTAG_INDIRECT);
}

pub inline fn VARATT_IS_EXTERNAL_EXPANDED_RO(PTR: anytype) @TypeOf((VARATT_IS_EXTERNAL(PTR) != 0) and (VARTAG_EXTERNAL(PTR) == VARTAG_EXPANDED_RO)) {
    return (VARATT_IS_EXTERNAL(PTR) != 0) and (VARTAG_EXTERNAL(PTR) == VARTAG_EXPANDED_RO);
}

pub inline fn VARATT_IS_EXTERNAL_EXPANDED_RW(PTR: anytype) @TypeOf((VARATT_IS_EXTERNAL(PTR) != 0) and (VARTAG_EXTERNAL(PTR) == VARTAG_EXPANDED_RW)) {
    return (VARATT_IS_EXTERNAL(PTR) != 0) and (VARTAG_EXTERNAL(PTR) == VARTAG_EXPANDED_RW);
}

pub inline fn VARATT_IS_EXTERNAL_EXPANDED(PTR: anytype) @TypeOf((VARATT_IS_EXTERNAL(PTR) != 0) and (VARTAG_IS_EXPANDED(VARTAG_EXTERNAL(PTR)) != 0)) {
    return (VARATT_IS_EXTERNAL(PTR) != 0) and (VARTAG_IS_EXPANDED(VARTAG_EXTERNAL(PTR)) != 0);
}

pub inline fn VARATT_IS_EXTERNAL_NON_EXPANDED(PTR: anytype) @TypeOf((VARATT_IS_EXTERNAL(PTR) != 0) and !(VARTAG_IS_EXPANDED(VARTAG_EXTERNAL(PTR)) != 0)) {
    return (VARATT_IS_EXTERNAL(PTR) != 0) and !(VARTAG_IS_EXPANDED(VARTAG_EXTERNAL(PTR)) != 0);
}

pub inline fn VARATT_IS_SHORT(PTR: anytype) @TypeOf(VARATT_IS_1B(PTR)) {
    return VARATT_IS_1B(PTR);
}

pub inline fn VARATT_IS_EXTENDED(PTR: anytype) @TypeOf(!(VARATT_IS_4B_U(PTR) != 0)) {
    return !(VARATT_IS_4B_U(PTR) != 0);
}

pub inline fn SET_VARSIZE(PTR: anytype, len: anytype) @TypeOf(SET_VARSIZE_4B(PTR, len)) {
    return SET_VARSIZE_4B(PTR, len);
}

pub inline fn SET_VARSIZE_SHORT(PTR: anytype, len: anytype) @TypeOf(SET_VARSIZE_1B(PTR, len)) {
    return SET_VARSIZE_1B(PTR, len);
}

pub inline fn SET_VARSIZE_COMPRESSED(PTR: anytype, len: anytype) @TypeOf(SET_VARSIZE_4B_C(PTR, len)) {
    return SET_VARSIZE_4B_C(PTR, len);
}

pub inline fn SET_VARTAG_EXTERNAL(PTR: anytype, tag: anytype) @TypeOf(SET_VARTAG_1B_E(PTR, tag)) {
    return SET_VARTAG_1B_E(PTR, tag);
}

pub inline fn VARSIZE_ANY(PTR: anytype) @TypeOf(if (VARATT_IS_1B_E(PTR)) VARSIZE_EXTERNAL(PTR) else if (VARATT_IS_1B(PTR)) VARSIZE_1B(PTR) else VARSIZE_4B(PTR)) {
    return if (VARATT_IS_1B_E(PTR)) VARSIZE_EXTERNAL(PTR) else if (VARATT_IS_1B(PTR)) VARSIZE_1B(PTR) else VARSIZE_4B(PTR);
}

pub inline fn VARSIZE_ANY_EXHDR(PTR: anytype) @TypeOf(if (VARATT_IS_1B_E(PTR)) VARSIZE_EXTERNAL(PTR) - VARHDRSZ_EXTERNAL else if (VARATT_IS_1B(PTR)) VARSIZE_1B(PTR) - VARHDRSZ_SHORT else VARSIZE_4B(PTR) - VARHDRSZ) {
    _ = &PTR;
    return if (VARATT_IS_1B_E(PTR)) VARSIZE_EXTERNAL(PTR) - VARHDRSZ_EXTERNAL else if (VARATT_IS_1B(PTR)) VARSIZE_1B(PTR) - VARHDRSZ_SHORT else VARSIZE_4B(PTR) - VARHDRSZ;
}

// pub inline fn VARSIZE_ANY_EXHDR(PTR: anytype) @TypeOf(if (VARATT_IS_1B_E(PTR)) VARSIZE_EXTERNAL(PTR) - VARHDRSZ_EXTERNAL else if (VARATT_IS_1B(PTR)) VARSIZE_1B(PTR) - VARHDRSZ_SHORT else VARSIZE_4B(PTR) - VARHDRSZ) {
//     return if (VARATT_IS_1B_E(PTR)) VARSIZE_EXTERNAL(PTR) - VARHDRSZ_EXTERNAL else if (VARATT_IS_1B(PTR)) VARSIZE_1B(PTR) - VARHDRSZ_SHORT else VARSIZE_4B(PTR) - VARHDRSZ;
// }

pub inline fn VARDATA_ANY(PTR: anytype) @TypeOf(if (VARATT_IS_1B(PTR)) VARDATA_1B(PTR) else VARDATA_4B(PTR)) {
    return if (VARATT_IS_1B(PTR)) VARDATA_1B(PTR) else VARDATA_4B(PTR);
}

pub inline fn VARDATA_COMPRESSED_GET_EXTSIZE(PTR: anytype) @TypeOf(@import("std").zig.c_translation.cast([*c]varattrib_4b, PTR).*.va_compressed.va_tcinfo & VARLENA_EXTSIZE_MASK) {
    return @import("std").zig.c_translation.cast([*c]varattrib_4b, PTR).*.va_compressed.va_tcinfo & VARLENA_EXTSIZE_MASK;
}

pub inline fn VARDATA_COMPRESSED_GET_COMPRESS_METHOD(PTR: anytype) @TypeOf(@import("std").zig.c_translation.cast([*c]varattrib_4b, PTR).*.va_compressed.va_tcinfo >> VARLENA_EXTSIZE_BITS) {
    return @import("std").zig.c_translation.cast([*c]varattrib_4b, PTR).*.va_compressed.va_tcinfo >> VARLENA_EXTSIZE_BITS;
}

pub inline fn VARATT_EXTERNAL_GET_EXTSIZE(toast_pointer: anytype) @TypeOf(toast_pointer.va_extinfo & VARLENA_EXTSIZE_MASK) {
    return toast_pointer.va_extinfo & VARLENA_EXTSIZE_MASK;
}

pub inline fn VARATT_EXTERNAL_GET_COMPRESS_METHOD(toast_pointer: anytype) @TypeOf(toast_pointer.va_extinfo >> VARLENA_EXTSIZE_BITS) {
    return toast_pointer.va_extinfo >> VARLENA_EXTSIZE_BITS;
}

pub inline fn VARATT_EXTERNAL_IS_COMPRESSED(toast_pointer: anytype) @TypeOf(VARATT_EXTERNAL_GET_EXTSIZE(toast_pointer) < (toast_pointer.va_rawsize - VARHDRSZ)) {
    return VARATT_EXTERNAL_GET_EXTSIZE(toast_pointer) < (toast_pointer.va_rawsize - VARHDRSZ);
}
