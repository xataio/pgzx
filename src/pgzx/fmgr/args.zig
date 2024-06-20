const std = @import("std");
const pg = @import("pgzx_pgsys");
const datum = @import("../datum.zig");

/// Index function argument type.
pub fn Arg(comptime T: type, comptime argNum: u32) type {
    return struct {
        const Self = @This();

        /// Reads the argument from the PostgreSQL function call information.
        pub inline fn read(fcinfo: pg.FunctionCallInfo) !T {
            return readArg(T, fcinfo, argNum);
        }

        /// Returns the type of the argument.
        pub inline fn getType() type {
            return ArgType(T);
        }
    };
}

/// The type of a function argument.
pub fn ArgType(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Computes the indexed type of a function argument.
        pub inline fn getForIndex(self: Self, argNum: u32) type {
            _ = self;
            return Arg(T, argNum);
        }

        pub inline fn isCallInfo() bool {
            return T == pg.FunctionCallInfo;
        }

        pub inline fn consumesArgument() bool {
            return !Self.isCallInfo();
        }

        /// Reads the indexed function argument.
        pub inline fn read(fcinfo: pg.FunctionCallInfo, argNum: u32) !T {
            return readArg(T, fcinfo, argNum);
        }
    };
}

inline fn readArgType(comptime T: type) type {
    if (T == pg.FunctionCallInfo) {
        return T;
    }
    return datum.findConv(T).Type;
}

/// Reads a postgres function call argument as a given type.
fn readArg(comptime T: type, fcinfo: pg.FunctionCallInfo, argNum: u32) !readArgType(T) {
    if (T == pg.FunctionCallInfo) {
        return fcinfo;
    }
    const converter = comptime datum.findConv(T);
    return converter.fromNullableDatum(try mustGetArgNullable(fcinfo, argNum));
}

fn readOptionalArg(comptime T: type, fcinfo: pg.FunctionCallInfo, argNum: u32) !?T {
    if (isNullArg(fcinfo, argNum)) {
        return null;
    }
    return readArg(T, fcinfo, argNum);
}

pub inline fn mustGetArgNullable(fcinfo: pg.FunctionCallInfo, argNum: u32) !pg.NullableDatum {
    if (fcinfo.*.nargs < argNum) {
        return error.NotEnoughArguments;
    }
    return fcinfo.*.args()[argNum];
}

pub inline fn mustGetArgDatum(fcinfo: pg.FunctionCallInfo, argNum: u32) !pg.Datum {
    if (isNullArg(fcinfo, argNum)) {
        return error.ArgumentIsNull;
    }
    return getArgDatum(fcinfo, argNum);
}

pub inline fn getArgDatum(fcinfo: pg.FunctionCallInfo, argNum: u32) pg.Datum {
    return fcinfo.*.args()[argNum].value;
}

pub inline fn isNullArg(fcinfo: pg.FunctionCallInfo, argNum: u32) bool {
    return fcinfo.*.args()[argNum].isnull;
}
