const std = @import("std");
const pgzx = @import("pgzx");
const pg = pgzx.c;

comptime {
    pgzx.PG_MODULE_MAGIC();

    pgzx.PG_FUNCTION_V1("query_by_id", query_by_id);
    pgzx.PG_FUNCTION_V1("query_by_value", query_by_value);
    pgzx.PG_FUNCTION_V1("ins_value", ins_value);
    pgzx.PG_FUNCTION_V1("test_iter", test_iter);
    pgzx.PG_FUNCTION_V1("test_rows_of", test_rows_of);
}

const SCHEMA_NAME = "spi_sql";
const TABLE_NAME = SCHEMA_NAME ++ ".tbl";

fn query_by_id(id: u32) ![]const u8 {
    const QUERY = "SELECT value FROM " ++ TABLE_NAME ++ " WHERE id = $1";

    try pgzx.spi.connect();
    defer pgzx.spi.finish();

    var rows = try pgzx.spi.query(QUERY, .{
        .limit = 1,
        .args = .{
            .types = &[_]pg.Oid{pg.INT4OID},
            .values = &[_]pg.NullableDatum{try pgzx.datum.toNullableDatum(id)},
        },
    });
    defer rows.deinit();

    if (!rows.next()) {
        return pgzx.elog.Error(@src(), "Unknown id: {d}", .{id});
    }

    var value: []const u8 = undefined;
    try rows.scan(.{&value});
    return value;
}

fn query_by_value(value: []const u8) !u32 {
    const QUERY = "SELECT id FROM " ++ TABLE_NAME ++ " WHERE value = $1";

    try pgzx.spi.connect();
    defer pgzx.spi.finish();

    // Use `RowsOf` to implicitey scan the result without having to declare temporary variables.

    var rows = pgzx.spi.RowsOf(u32).init(try pgzx.spi.query(QUERY, .{
        .limit = 1,
        .args = .{
            .types = &[_]pg.Oid{pg.TEXTOID},
            .values = &[_]pg.NullableDatum{try pgzx.datum.toNullableDatum(value)},
        },
    }));
    defer rows.deinit();

    if (try rows.next()) |id| {
        return id;
    }
    return pgzx.elog.Error(@src(), "Value '{s}' not found", .{value});
}

fn ins_value(id: u32, value: []const u8) !u32 {
    const STMT = "INSERT INTO " ++ TABLE_NAME ++ " (id, value) VALUES ($1, $2) RETURNING id";

    try pgzx.spi.connect();
    defer pgzx.spi.finish();

    var rows = pgzx.spi.RowsOf(u32).init(try pgzx.spi.query(STMT, .{
        .args = .{
            .types = &[_]pg.Oid{
                pg.INT4OID,
                pg.TEXTOID,
            },
            .values = &[_]pg.NullableDatum{
                try pgzx.datum.toNullableDatum(id),
                try pgzx.datum.toNullableDatum(value),
            },
        },
    }));
    defer rows.deinit();

    if (try rows.next()) |ret_id| {
        return ret_id;
    }
    unreachable;
}

fn test_iter() !void {
    const QUERY = "SELECT id, value FROM " ++ TABLE_NAME;
    const Record = struct {
        id: u32,
        value: []const u8,
    };

    try pgzx.spi.connect();
    defer pgzx.spi.finish();

    var rows = try pgzx.spi.query(QUERY, .{});
    defer rows.deinit();

    while (rows.next()) {
        var rec: Record = undefined;

        try rows.scan(.{&rec});
        pgzx.elog.Info(@src(), "id: {d}, value: {s}", .{ rec.id, rec.value });
    }
}

fn test_rows_of() !void {
    const QUERY = "SELECT id, value FROM " ++ TABLE_NAME;
    const Record = struct {
        id: u32,
        value: []const u8,
    };

    try pgzx.spi.connect();
    defer pgzx.spi.finish();

    var rows = pgzx.spi.RowsOf(Record).init(try pgzx.spi.query(QUERY, .{}));
    defer rows.deinit();

    while (try rows.next()) |rec| {
        pgzx.elog.Info(@src(), "id: {d}, value: {s}", .{ rec.id, rec.value });
    }
}
