const std = @import("std");
const pg = @import("pgzx_pgsys");

const meta = @import("meta.zig");
const mem = @import("mem.zig");
const err = @import("err.zig");
const datum = @import("datum.zig");

pub fn connect() err.PGError!void {
    const status = pg.SPI_connect();
    if (status == pg.SPI_ERROR_CONNECT) {
        return err.PGError.SPIConnectFailed;
    }
}

pub fn connectNonAtomic() err.PGError!void {
    const status = pg.SPI_connect_ext(pg.SPI_OPT_NONATOMIC);
    try checkStatus(status);
}

pub fn finish() void {
    _ = pg.SPI_finish();
}

pub const Args = struct {
    types: []const pg.Oid,
    values: []const pg.NullableDatum,

    pub fn has_nulls(self: *const Args) bool {
        for (self.values) |value| {
            if (value.isnull) {
                return true;
            }
        }
        return false;
    }
};

pub const ExecOptions = struct {
    read_only: bool = false,
    limit: c_long = 0,
    args: ?Args = null,
};

pub const SPIError = err.PGError || std.mem.Allocator.Error;

pub fn exec(sql: [:0]const u8, options: ExecOptions) SPIError!isize {
    const ret = try execImpl(sql, options);
    var rows = Rows.init();
    defer rows.deinit();
    return @intCast(ret);
}

pub fn query(sql: [:0]const u8, options: ExecOptions) SPIError!Rows {
    _ = try execImpl(sql, options);
    return Rows.init();
}

pub fn queryTyped(comptime T: type, sql: [:0]const u8, options: ExecOptions) SPIError!RowsOf(T) {
    const rows = try query(sql, options);
    return rows.typed(T);
}

fn execImpl(sql: [:0]const u8, options: ExecOptions) SPIError!c_int {
    if (options.args) |args| {
        if (args.types.len != args.values.len) {
            return err.PGError.SPIArgument;
        }

        var arena = std.heap.ArenaAllocator.init(mem.PGCurrentContextAllocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const n = args.types.len;
        const nulls: [*c]const u8 = blk: {
            if (args.has_nulls()) {
                var buf = try allocator.alloc(u8, n);
                for (args.values, 0..) |value, i| {
                    buf[i] = if (value.isnull) 'n' else ' ';
                }
                break :blk buf.ptr;
            } else {
                break :blk null;
            }
        };

        const values: [*c]pg.Datum = blk: {
            var buf = try allocator.alloc(pg.Datum, n);
            for (args.values, 0..) |arg, i| {
                buf[i] = arg.value;
            }
            break :blk buf.ptr;
        };

        const status = pg.SPI_execute_with_args(
            sql.ptr,
            @intCast(n),
            @constCast(args.types.ptr),
            values,
            nulls,
            options.read_only,
            options.limit,
        );
        try checkStatus(status);
        return status;
    } else {
        const status = pg.SPI_execute(sql.ptr, options.read_only, options.limit);
        try checkStatus(status);
        return status;
    }
}

fn scanProcessed(row: usize, values: anytype) !void {
    scanProcessedFrame(SPIFrame.get(), row, values);
}

inline fn scanProcessedFrame(frame: SPIFrame, row: usize, values: anytype) !void {
    var column: c_int = 1;
    inline for (std.meta.fields(@TypeOf(values)), 0..) |field, i| {
        column = try scanField(field.type, frame, values[i], row, column);
    }
}

fn scanField(
    comptime fieldType: type,
    frame: SPIFrame,
    to: anytype,
    row: usize,
    column: c_int,
) !c_int {
    const field_info = @typeInfo(fieldType);
    if (field_info != .Pointer) {
        @compileError("scanField requires a pointer");
    }
    if (field_info.Pointer.size == .Slice) {
        @compileError("scanField requires a single pointer, not a slice");
    }

    const child_type = field_info.Pointer.child;
    if (@typeInfo(child_type) == .Struct) {
        var struct_column = column;
        inline for (std.meta.fields(child_type)) |field| {
            const child_ptr = &@field(to.*, field.name);
            struct_column = try scanField(@TypeOf(child_ptr), frame, child_ptr, row, struct_column);
        }
        return struct_column;
    } else {
        const value = try convBinValue(child_type, frame, row, column);
        to.* = value;
        return column + 1;
    }
}

pub fn OwnedSPIFrameRows(comptime R: type) type {
    return struct {
        rows: R,

        const Self = @This();

        pub inline fn init(r: R) Self {
            return .{ .rows = r };
        }

        pub inline fn deinit(self: *Self) void {
            self.rows.deinit();
            finish();
        }

        pub fn next(self: *Self) meta.fnReturnType(@TypeOf(R.next)) {
            return self.rows.next();
        }

        pub const scan = if (@hasField(R, "scan"))
            R.scan
        else
            @compileError("no scan method available");
    };
}

// Rows iterates over SPI_tuptable from the last executed SPI query.
// When initializing a Rows iterator we capture the current SPI_tuptable from
// the active SPI frame.
//
// Safety:
// =======
//
// The underlying tuple table is released when the current frame is released
// via `finish`. The iterator must not be used after. We have no way to check
// if the current frame was released or not. Accessing the tuple table after a
// release will result in undefined behavior.
//
// Due to SPI managing a stack of SPI frames it is safe to use `connect` to
// create a child frame to run queries while iterating over the rows.
//
pub const Rows = struct {
    row: isize,
    spi_frame: SPIFrame,

    fn init() Rows {
        return .{
            .row = -1,
            .spi_frame = SPIFrame.get(),
        };
    }

    fn typed(self: Rows, comptime T: type) RowsOf(T) {
        return RowsOf(T).init(self);
    }

    fn ownedSPIFrame(self: Rows) OwnedSPIFrameRows(Rows) {
        return OwnedSPIFrameRows(Rows).init(self);
    }

    pub fn deinit(self: *Rows) void {
        if (self.spi_frame.tuptable) |tt| {
            pg.SPI_freetuptable(tt);
        }
        self.row = -1;
    }

    pub fn next(self: *Rows) bool {
        const next_idx = self.row + 1;
        if (self.spi_frame.tuptable == null or next_idx >= self.spi_frame.processed) {
            return false;
        }
        self.row = next_idx;
        return true;
    }

    pub fn scan(self: *Rows, values: anytype) !void {
        if (self.row < 0) {
            return err.PGError.SPIInvalidRowIndex;
        }
        try scanProcessedFrame(self.spi_frame, @intCast(self.row), values);
    }
};

pub fn RowsOf(comptime T: type) type {
    return struct {
        rows: Rows,

        const Self = @This();
        pub const Owned = OwnedSPIFrameRows(Self);

        pub fn init(rows: Rows) Self {
            return .{ .rows = rows };
        }

        pub fn deinit(self: *Self) void {
            self.rows.deinit();
        }

        pub fn ownedSPIFrame(self: Self) Self.Owned {
            return OwnedSPIFrameRows(Self).init(self);
        }

        pub fn next(self: *Self) !?T {
            if (!self.rows.next()) {
                return null;
            }
            var value: T = undefined;
            try self.rows.scan(.{&value});
            return value;
        }
    };
}

// The SPI interface uses a
const SPIFrame = struct {
    processed: u64,
    tuptable: ?*pg.SPITupleTable,

    inline fn get() SPIFrame {
        return .{
            .processed = pg.SPI_processed,
            .tuptable = pg.SPI_tuptable,
        };
    }
};

pub fn convProcessed(comptime T: type, row: c_int, col: c_int) !T {
    if (pg.SPI_processed <= row) {
        return err.PGError.SPIInvalidRowIndex;
    }
    return convBinValue(T, SPIFrame.get(), row, col);
}

pub fn convBinValue(comptime T: type, frame: SPIFrame, row: usize, col: c_int) !T {
    // TODO: check index?

    var nd: pg.NullableDatum = undefined;
    const table = frame.tuptable.?;
    const desc = table.*.tupdesc;
    nd.value = pg.SPI_getbinval(table.*.vals[row], desc, col, @ptrCast(&nd.isnull));
    try checkStatus(pg.SPI_result);
    const attr_desc = &desc.*.attrs()[@intCast(col - 1)];
    const oid = attr_desc.atttypid;
    return try datum.fromNullableDatumWithOID(T, nd, oid);
}

fn checkStatus(st: c_int) err.PGError!void {
    switch (st) {
        pg.SPI_ERROR_CONNECT => return err.PGError.SPIConnectFailed,
        pg.SPI_ERROR_ARGUMENT => return err.PGError.SPIArgument,
        pg.SPI_ERROR_COPY => return err.PGError.SPICopy,
        pg.SPI_ERROR_TRANSACTION => return err.PGError.SPITransaction,
        pg.SPI_ERROR_OPUNKNOWN => return err.PGError.SPIOpUnknown,
        pg.SPI_ERROR_UNCONNECTED => return err.PGError.SPIUnconnected,
        pg.SPI_ERROR_NOATTRIBUTE => return err.PGError.SPINoAttribute,
        else => {
            if (st < 0) {
                return err.PGError.SPIError;
            }
        },
    }
}
