const std = @import("std");
const c = @import("../c.zig");
const conv = @import("conv.zig");

/// Index function argument type.
pub fn Arg(comptime T: type, comptime argNum: u32) type {
    return struct {
        const Self = @This();

        /// Reads the argument from the PostgreSQL function call information.
        pub inline fn read(fcinfo: c.FunctionCallInfo) !T {
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
            return T == c.FunctionCallInfo;
        }

        pub inline fn consumesArgument() bool {
            return !Self.isCallInfo();
        }

        /// Reads the indexed function argument.
        pub inline fn read(fcinfo: c.FunctionCallInfo, argNum: u32) !T {
            return readArg(T, fcinfo, argNum);
        }
    };
}

inline fn readArgType(comptime T: type) type {
    if (T == c.FunctionCallInfo) {
        return T;
    }
    return conv.find(T).Type;
}

/// Reads a postgres function call argument as a given type.
fn readArg(comptime T: type, fcinfo: c.FunctionCallInfo, argNum: u32) !readArgType(T) {
    if (T == c.FunctionCallInfo) {
        return fcinfo;
    }
    const converter = comptime conv.find(T);
    return converter.fromNullableDatum(try mustGetArgNullable(fcinfo, argNum));
}

fn readOptionalArg(comptime T: type, fcinfo: c.FunctionCallInfo, argNum: u32) !?T {
    if (isNullArg(fcinfo, argNum)) {
        return null;
    }
    return readArg(T, fcinfo, argNum);
}

pub inline fn mustGetArgNullable(fcinfo: c.FunctionCallInfo, argNum: u32) !c.NullableDatum {
    if (fcinfo.*.nargs < argNum) {
        return error.NotEnoughArguments;
    }
    return fcinfo.*.args()[argNum];
}

pub inline fn mustGetArgDatum(fcinfo: c.FunctionCallInfo, argNum: u32) !c.Datum {
    if (isNullArg(fcinfo, argNum)) {
        return error.ArgumentIsNull;
    }
    return getArgDatum(fcinfo, argNum);
}

pub inline fn getArgDatum(fcinfo: c.FunctionCallInfo, argNum: u32) c.Datum {
    return fcinfo.*.args()[argNum].value;
}

pub inline fn isNullArg(fcinfo: c.FunctionCallInfo, argNum: u32) bool {
    return fcinfo.*.args()[argNum].isnull;
}
