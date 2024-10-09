const std = @import("std");

const pg = @import("pgzx_pgsys");

const elog = @import("elog.zig");
const datum = @import("datum.zig");
const meta = @import("meta.zig");

pub const args = @import("fmgr/args.zig");
pub const varatt = pg.varatt;

pub const Pg_magic_struct = pg.Pg_magic_struct;
pub const Pg_finfo_record = pg.Pg_finfo_record;

pub const MAGIC = [*c]const Pg_magic_struct;
pub const FN_INFO_V1 = [*c]const Pg_finfo_record;

/// Use PG_MAGIC value to indicate to PostgreSQL that we have a loadable module.
/// This value must be returned by a function named `Pg_magic_func`.
pub const PG_MAGIC = Pg_magic_struct{
    .len = @bitCast(@as(c_uint, @truncate(@sizeOf(Pg_magic_struct)))),
    .version = @divTrunc(pg.PG_VERSION_NUM, @as(c_int, 100)),
    .funcmaxargs = pg.FUNC_MAX_ARGS,
    .indexmaxkeys = pg.INDEX_MAX_KEYS,
    .namedatalen = pg.NAMEDATALEN,
    .float8byval = pg.FLOAT8PASSBYVAL,
    .abi_extra = [32]u8{ 'P', 'o', 's', 't', 'g', 'r', 'e', 'S', 'Q', 'L', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
};

/// Postgres magic indicator that a function uses the v1 UDF API.
pub const PG_FINFO_V1_RECORD = Pg_finfo_record{
    .api_version = 1,
};

/// Magic PostgreSQL symbols to indicate it's a loadable module.
///
/// We do not export the symbol to postgres. If you want to indicate that you have a loadable module
/// use `Pg_magic_func` like so in your module:
///
///   pub export fn Pg_magic_func() [*c]const pg.Pg_magic_struct {
///     return pgzx.Pg_magic_func();
///   }
///
pub inline fn PG_MODULE_MAGIC() void {
    @export(&Pg_magic_func, .{ .name = "Pg_magic_func" });
}

fn Pg_magic_func() callconv(.C) [*c]const Pg_magic_struct {
    return &PG_MAGIC;
}

pub fn FunctionV1() callconv(.C) [*c]const Pg_finfo_record {
    return &PG_FINFO_V1_RECORD;
}

pub inline fn PG_FUNCTION_INFO_V1(comptime fun: []const u8) void {
    const finfo_name = "pg_finfo_" ++ fun;
    @export(&FunctionV1, .{ .name = finfo_name });
}

pub inline fn PG_FUNCTION_V1(comptime name: []const u8, comptime callback: anytype) void {
    PG_FUNCTION_INFO_V1(name);

    const reg = genFnCall(callback);
    @export(&reg.call, .{ .name = name });
}

pub inline fn PG_EXPORT(comptime mod: type) void {
    const decls = switch (@typeInfo(mod)) {
        .@"struct" => |s| s.decls,
        else => @compileError("PG_EXPORT requires a struct"),
    };

    inline for (decls) |decl| {
        const value = @field(mod, decl.name);
        const ft = @typeInfo(@TypeOf(value));
        if (ft != .@"fn" or ft.@"fn".is_generic or ft.@"fn".is_var_args) {
            continue;
        }
        PG_FUNCTION_V1(decl.name, value);
    }
}

inline fn genFnCall(comptime f: anytype) type {
    return struct {
        const function: @TypeOf(f) = f;
        fn call(fcinfo: pg.FunctionCallInfo) callconv(.C) pg.Datum {
            return pgCall(@src(), function, fcinfo);
        }
    };
}

pub const Arg = args.Arg;
pub const ArgType = args.ArgType;

pub inline fn pgCall(
    comptime src: std.builtin.SourceLocation,
    comptime impl: anytype,
    fcinfo: pg.FunctionCallInfo,
) pg.Datum {
    const fnType = @TypeOf(impl);
    const funcArgType = std.meta.ArgsTuple(fnType);

    var callArgs: funcArgType = undefined;
    comptime var info_idx = 0;
    inline for (std.meta.fields(@TypeOf(callArgs)), 0..) |field, i| {
        const arg = ArgType(field.type);
        callArgs[i] = arg.read(fcinfo, info_idx) catch |e| elog.throwAsPostgresError(src, e);
        if (arg.consumesArgument()) {
            info_idx += 1;
        }
    }

    const value = switch (@typeInfo(meta.fnReturnType(fnType))) {
        .error_union, .error_set => @call(.no_async, impl, callArgs) catch |e| elog.throwAsPostgresError(src, e),
        else => @call(.no_async, impl, callArgs),
    };

    const result_conv = datum.findConv(@TypeOf(value));
    const nullable_datum = result_conv.toNullableDatum(value) catch |e| elog.throwAsPostgresError(src, e);
    if (nullable_datum.isnull) {
        fcinfo.*.isnull = true;
        return 0;
    }
    return nullable_datum.value;
}
