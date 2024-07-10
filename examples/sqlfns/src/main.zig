// With this extension we want to show you how you can use pgzx to create
// and export functions to PostgreSQL.

// First we want to import some dependencies and declare this shared library as a postgres module via PG_MODULE_MAGIC.

const std = @import("std");
const pgzx = @import("pgzx");
const pg = pgzx.c;

comptime {
    pgzx.PG_MODULE_MAGIC();
}

// Exorted functions with C calling convention
// ===========================================

// It is always possible to export a function by writing a C function directly.
// The functions accepts the FunctionCallInfoData struct and must return a Datum and no Zig errors.
//

export fn pg_finfo_hello_world_c() callconv(.C) [*c]const pg.Pg_finfo_record {
    return pgzx.fmgr.FunctionV1();
}

export fn hello_world_c(fcinfo: pg.FunctionCallInfo) callconv(.C) pg.Datum {
    // When using the C interface we can not use any of the PG_RETURN or PG_GETARG macros directly.
    //
    // This function accepts a 'string' of type 'text' and returns a new string of type 'text'.
    // We start by getting the first argument of the function call.
    //
    // The pgzx.fmgr and ppgzx.fmgr.args modules provide a set of functions to
    // work with the FunctionCallInfoData struct.

    const arg = pgzx.fmgr.args.mustGetArgNullable(fcinfo, 0) catch {
        pgzx.elog.ErrorThrow(@src(), "missing argument", .{});
        unreachable;
    };

    const message = if (arg.isnull) "Hello World" else blk: {
        const name = pgzx.datum.getDatumTextSliceZ(arg.value) catch |e| {
            pgzx.elog.throwAsPostgresError(@src(), e);
            unreachable;
        };

        const allocator = pgzx.mem.PGCurrentContextAllocator;
        const hello = std.fmt.allocPrintZ(allocator, "Hello, {s}!", .{name}) catch |e| {
            pgzx.elog.throwAsPostgresError(@src(), e);
            unreachable;
        };
        break :blk hello;
    };

    return pgzx.datum.sliceToDatumTextZ(message) catch |e| {
        pgzx.elog.throwAsPostgresError(@src(), e);
        unreachable;
    };
}

// Use PG_FUNCTION_V1 to declare and export a zig function
// =======================================================

// Let's write the same function using the fmgr module to declare and export the module for us.
//
// Similar to extension written in C we use PG_FUNCTION_V1 to declare the function. This will produce a wrapper
// also exporting our function to PostgreSQL. The wrapper checks the argument and return type of your function
// and implements argument unpacking, return value packing and Zig error to PostgreSQL error conversion.

comptime {
    pgzx.PG_FUNCTION_V1("hello_world_zig", hello_world_zig);
}

fn hello_world_zig(name: ?[:0]const u8) ![:0]const u8 {
    return if (name) |n|
        try std.fmt.allocPrintZ(pgzx.mem.PGCurrentContextAllocator, "Hello, {s}!", .{n})
    else
        "Hello World";
}

// We can also write a variant that will return `NULL` when the argument is null. All we have to do is to return an optional value like so:

comptime {
    pgzx.PG_FUNCTION_V1("hello_world_zig_null", hello_world_zig_null);
}

fn hello_world_zig_null(name: ?[:0]const u8) !?[:0]const u8 {
    return if (name) |n|
        try std.fmt.allocPrintZ(pgzx.mem.PGCurrentContextAllocator, "Hello, {s}!", .{n})
    else
        null;
}

// It is also possible to capture the FunctionCallInfo as an argument to your function. You want to do this if
// you want to use the configured collation, check the context node, or
// manually parse arguments manually.
//
// In this example we will accept and return a Datum. This requires to mark a
// NULL return in the FunctionCallInfo.

comptime {
    pgzx.PG_FUNCTION_V1("hello_world_zig_datum", hello_world_zig_datum);
}

fn hello_world_zig_datum(fcinfo: pg.FunctionCallInfo, arg: ?pg.Datum) !pg.Datum {
    if (arg == null) {
        fcinfo.*.isnull = true;
        return 0;
    }

    const name = try pgzx.datum.getDatumTextSliceZ(arg.?);
    const message = try std.fmt.allocPrintZ(pgzx.mem.PGCurrentContextAllocator, "Hello, {s}!", .{name});
    return try pgzx.datum.sliceToDatumTextZ(message);
}

// PG_EXPORT: Export all public functions from a struct
// ====================================================

// Exporting a number of functions can become a bit tedious over time.
// The `PG_EXPORT` function can be used to automatically export all public functions from a struct.

// Here we export a function from an anonymous struct.
comptime {
    pgzx.PG_EXPORT(struct {
        pub fn hello_world_anon(name: ?[:0]const u8) ![:0]const u8 {
            return if (name) |n|
                try std.fmt.allocPrintZ(pgzx.mem.PGCurrentContextAllocator, "Hello, {s}!", .{n})
            else
                "Hello World";
        }
    });
}

// Or a names struct:

comptime {
    pgzx.PG_EXPORT(mod_hello_world);
}

const mod_hello_world = struct {
    pub fn hello_world_mod(name: ?[:0]const u8) ![:0]const u8 {
        return if (name) |n|
            try std.fmt.allocPrintZ(pgzx.mem.PGCurrentContextAllocator, "Hello, {s}!", .{n})
        else
            "Hello World";
    }
};

// In Zig when importing a file, the file is treated as a struct. Let's try this:

comptime {
    pgzx.PG_EXPORT(@import("hello_world.zig"));
}
