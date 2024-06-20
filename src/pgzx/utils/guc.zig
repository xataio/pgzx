const std = @import("std");

const pg = @import("pgzx_pgsys");

pub const CustomBoolVariable = struct {
    value: bool,

    pub const Options = struct {
        name: [:0]const u8,
        short_desc: ?[:0]const u8 = null,
        long_desc: ?[:0]const u8 = null,
        initial_value: bool = false,
        context: pg.GucContext = pg.PGC_USERSET,
        flags: c_int = 0,
        check_hook: pg.GucBoolCheckHook = null,
        assign_hook: pg.GucBoolAssignHook = null,
        show_hook: pg.GucShowHook = null,
    };

    pub fn registerValue(options: Options) void {
        doRegister(null, options);
    }

    pub fn register(self: *CustomBoolVariable, options: Options) void {
        self.value = options.initial_value;
        doRegister(&self.value, options);
    }

    fn doRegister(value: ?*bool, options: Options) void {
        pg.DefineCustomBoolVariable(
            options.name,
            optSliceCPtr(options.short_desc),
            optSliceCPtr(options.long_desc),
            value,
            options.initial_value,
            options.context,
            options.flags,
            options.check_hook,
            options.assign_hook,
            options.show_hook,
        );
    }
};

pub const CustomIntVariable = struct {
    value: c_int,

    pub const Options = struct {
        name: [:0]const u8,
        short_desc: ?[:0]const u8 = null,
        long_desc: ?[:0]const u8 = null,
        initial_value: ?c_int = 0,
        min_value: c_int = 0,
        max_value: c_int = std.math.maxInt(c_int),
        context: pg.GucContext = pg.PGC_USERSET,
        flags: c_int = 0,
        check_hook: pg.GucIntCheckHook = null,
        assign_hook: pg.GucIntAssignHook = null,
        show_hook: pg.GucShowHook = null,
    };

    pub fn registerValue(options: Options) void {
        doRegister(null, options);
    }

    pub fn register(self: *CustomIntVariable, options: Options) void {
        if (options.initial_value) |v| {
            self.value = v;
        }
        doRegister(&self.value, options);
    }

    fn doRegister(value: ?*c_int, options: Options) void {
        const init_value = if (value) |v| v.* else options.initial_value orelse 0;
        pg.DefineCustomIntVariable(
            options.name,
            optSliceCPtr(options.short_desc),
            optSliceCPtr(options.long_desc),
            value,
            init_value,
            options.min_value,
            options.max_value,
            options.context,
            options.flags,
            options.check_hook,
            options.assign_hook,
            options.show_hook,
        );
    }
};

pub const CustomStringVariable = struct {
    _value: [*c]const u8 = null,

    pub const Options = struct {
        name: [:0]const u8,
        short_desc: ?[:0]const u8 = null,
        long_desc: ?[:0]const u8 = null,
        initial_value: ?[:0]const u8 = null,
        context: pg.GucContext = pg.PGC_USERSET,
        flags: c_int = 0,
    };

    pub fn register(self: *CustomStringVariable, options: Options) void {
        var initial_value: [*c]const u8 = null;
        if (options.initial_value) |v| {
            initial_value = v.ptr;
            self._value = v.ptr;
        }

        pg.DefineCustomStringVariable(
            options.name,
            optSliceCPtr(options.short_desc),
            optSliceCPtr(options.long_desc),
            @ptrCast(&self._value),
            initial_value,
            options.context,
            options.flags,
            null,
            null,
            null,
        );
    }

    pub fn ptr(self: *CustomStringVariable) [*c]const u8 {
        return self._value;
    }

    pub fn value(self: *CustomStringVariable) [:0]const u8 {
        if (self._value == null) {
            return "";
        }

        // TODO: use assign callback to precompute the length
        return std.mem.span(self._value);
    }
};

pub const CustomIntOptions = struct {
    name: [:0]const u8,
    short_desc: ?[:0]const u8 = null,
    long_desc: ?[:0]const u8 = null,
    value_addr: *c_int,
    boot_value: c_int = 0,
    min_value: c_int = 0,
    max_value: c_int = std.math.maxInt(c_int),
    context: pg.GucContext = pg.PGC_USERSET,
    flags: c_int = 0,
    check_hook: pg.GucIntCheckHook = null,
    assign_hook: pg.GucIntAssignHook = null,
    show_hook: pg.GucShowHook = null,
};

pub fn defineCustomInt(options: CustomIntOptions) void {
    pg.DefineCustomIntVariable(
        options.name,
        optSliceCPtr(options.short_desc),
        optSliceCPtr(options.long_desc),
        options.value_addr,
        options.boot_value,
        options.min_value,
        options.max_value,
        options.context,
        options.flags,
        options.check_hook,
        options.assign_hook,
        options.show_hook,
    );
}

fn optSliceCPtr(opt_slice: ?[:0]const u8) [*c]const u8 {
    if (opt_slice) |s| {
        return s.ptr;
    }
    return null;
}
