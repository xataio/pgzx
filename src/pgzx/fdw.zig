const std = @import("std");

const elog = @import("elog.zig");
const mem = @import("mem.zig");
const collections = @import("collections.zig");
const pg = @import("c.zig");

pub const DefElem = pg.DefElem;

pub fn defElemMatchName(def: *const pg.DefElem, name: []const u8) bool {
    return std.mem.eql(u8, name, std.mem.span(def.defname));
}

pub const DefElemList = collections.list.PointerListOf(DefElem);

pub const Option = struct {
    keyword: [:0]const u8,
    context: pg.Oid,
    validator: ?Validator = null,

    const Self = @This();

    pub const Validator = *const fn (*const pg.DefElem, pg.Oid) void;

    pub inline fn init(keyword: [:0]const u8, context: pg.Oid, validator: ?Validator) Self {
        return .{ .keyword = keyword, .context = context, .validator = validator };
    }

    pub inline fn String(keyword: [:0]const u8, context: pg.Oid) Self {
        return Self.init(keyword, context, validateString);
    }

    pub inline fn OptString(keyword: [:0]const u8, context: pg.Oid) Self {
        return Self.init(keyword, context, null);
    }

    pub inline fn Bool(keyword: [:0]const u8, context: pg.Oid) Self {
        return Self.init(keyword, context, validateBool);
    }

    pub inline fn Int(keyword: [:0]const u8, context: pg.Oid) Self {
        return Self.init(keyword, context, validateInt);
    }

    pub inline fn IntPos(keyword: [:0]const u8, context: pg.Oid) Self {
        return Self.init(keyword, context, validateIntPos);
    }

    pub inline fn IntPos0(keyword: [:0]const u8, context: pg.Oid) Self {
        return Self.init(keyword, context, validateIntPos0);
    }

    pub inline fn Real(keyword: [:0]const u8, context: pg.Oid) Self {
        return Self.init(keyword, context, validateReal);
    }

    pub inline fn RealPos(keyword: [:0]const u8, context: pg.Oid) Self {
        return Self.init(keyword, context, validateRealPos);
    }

    pub inline fn RealPos0(keyword: [:0]const u8, context: pg.Oid) Self {
        return Self.init(keyword, context, validateRealPos0);
    }

    pub inline fn Oid(keyword: [:0]const u8, context: pg.Oid) Self {
        return Self.init(keyword, context, validateOid);
    }

    pub fn matches(self: *const Self, name: []const u8, context: pg.Oid) bool {
        return (context == pg.InvalidOid or self.context == context) and std.mem.eql(u8, self.keyword, name);
    }

    pub fn matchesZ(self: *const Self, name: [:0]const u8, context: pg.Oid) bool {
        return (context == pg.InvalidOid or self.context == context) and std.mem.eql(u8, self.keyword, name);
    }

    pub fn validate(self: *const Self, def: *const pg.DefElem, catalog: pg.Oid) void {
        if (self.validator) |v| {
            v(def, catalog);
        }
    }
};

pub const OptionList = struct {
    elems: []const Option,

    pub fn init(elems: []const Option) OptionList {
        return .{ .elems = elems };
    }

    pub fn findOptionByName(self: *const OptionList, name: []const u8, context: pg.Oid) ?*const Option {
        for (self.elems) |*opt| {
            if (opt.matches(name, context)) {
                return opt;
            }
        }
        return null;
    }

    pub fn findOption(self: *const OptionList, def: *const DefElem, context: pg.Oid) ?*const Option {
        return self.findOptionByName(std.mem.span(def.defname), context);
    }

    pub fn findAndValidateOption(self: *const OptionList, def: *const DefElem, context: pg.Oid) ?*const Option {
        const opt = self.findOption(def, context);
        if (opt) |o| {
            o.validate(def, context);
            return o;
        }
        return null;
    }

    pub fn findClosestMatch(self: *const OptionList, def: *const DefElem, context: pg.Oid) ?*const Option {
        var match_state: pg.ClosestMatchState = undefined;
        pg.initClosestMatch(&match_state, def.defname, 4);

        var has_valid_option = false;
        for (self.elems) |opt| {
            if (opt.context == context) {
                has_valid_option = true;
                pg.updateClosestMatch(&match_state, opt.keyword.ptr);
            }
        }

        if (has_valid_option) {
            const match = pg.getClosestMatch(&match_state);
            if (match != null) {
                return self.findOptionByName(std.mem.span(match), context);
            }
        }
        return null;
    }
};

pub const MultiOptionList = struct {
    lists: []const OptionList,

    pub fn init(lists: []const OptionList) MultiOptionList {
        return .{ .lists = lists };
    }

    pub fn findOptionByName(self: *const MultiOptionList, name: []const u8, context: pg.Oid) ?*const Option {
        for (self.lists) |list| {
            const opt = list.findOptionByName(name, context);
            if (opt != null) {
                return opt;
            }
        }
        return null;
    }

    pub fn findOption(self: *const MultiOptionList, def: *const DefElem, context: pg.Oid) ?*const Option {
        self.findOptionByName(std.mem.span(def.defname), context);
    }

    pub fn findAndValidateOption(self: *const MultiOptionList, def: *const DefElem, context: pg.Oid) ?*const Option {
        for (self.lists) |list| {
            const opt = list.findAndValidateOption(def, context);
            if (opt != null) {
                return opt;
            }
        }
        return null;
    }

    pub fn findClosestMatch(self: *const MultiOptionList, def: *const DefElem, context: pg.Oid) ?*const Option {
        var match_state: pg.ClosestMatchState = undefined;
        pg.initClosestMatch(&match_state, def.defname, 4);

        var has_valid_option = false;
        for (self.lists) |list| {
            for (list.elems) |opt| {
                if (opt.context == context) {
                    has_valid_option = true;
                    pg.updateClosestMatch(&match_state, opt.keyword.ptr);
                }
            }
        }

        if (has_valid_option) {
            const match = pg.getClosestMatch(&match_state);
            if (match != null) {
                return self.findOptionByName(std.mem.span(match), context);
            }
        }
        return null;
    }
};

pub fn findOptionByName(list: []Option, name: []const u8, context: pg.Oid) ?*const Option {
    return OptionList.init(list).findOptionByName(name, context);
}

pub fn findOption(list: []Option, def: *const DefElem, context: pg.Oid) ?*const Option {
    return OptionList.init(list).findOption(def, context);
}

pub fn findAndValidateOption(list: []Option, def: *DefElem, context: pg.Oid) bool {
    return OptionList.init(list).findAndValidateOption(def, context);
}

pub fn listFindOption(list: ?*pg.List, name: []const u8) ?*const DefElem {
    var iter = DefElemList.iteratorFrom(list);
    while (iter.next()) |def| {
        if (defElemMatchName(def.?, name)) {
            return def;
        }
    }
    return null;
}

pub fn validateOptions(list: anytype, options: ?*pg.List, context: pg.Oid) void {
    var iter = DefElemList.iteratorFrom(options);
    while (iter.next()) |def| {
        const found = list.findAndValidateOption(def.?, context);
        if (found == null) {
            errorUnknownOption(list, def.?, context);
        }
    }
}

pub fn errorUnknownOption(list: anytype, def: *const DefElem, context: pg.Oid) void {
    var errctx = mem.getErrorContextThrowOOM();
    const err_alloc = errctx.allocator();

    const msg = std.fmt.allocPrintZ(err_alloc, "invalid option \"{s}\"", .{def.defname}) catch unreachable();

    var hint: [:0]const u8 = "There are no valid options in this context.";
    const match = list.findClosestMatch(def, context);
    if (match) |m| {
        hint = std.fmt.allocPrintZ(err_alloc, "did you mean \"{s}\"?", .{m.keyword}) catch unreachable();
    }

    elog.Report.init(@src(), pg.ERROR).pgRaise(.{
        .code = pg.ERRCODE_INVALID_PARAMETER_VALUE,
        .message = msg,
        .hint = hint,
    });
}

pub fn validateString(def: *const pg.DefElem, context: pg.Oid) void {
    _ = context;
    if (std.mem.len(pg.defGetString(@constCast(def))) == 0) {
        elog.ErrorThrow(@src(), "option {s} must not be empty", .{def.defname});
    }
}

pub fn getString(def: *const pg.DefElem) []const u8 {
    return std.mem.span(pg.defGetString(@constCast(def)));
}

pub fn getBool(def: *const pg.DefElem) bool {
    return pg.defGetBoolean(@constCast(def));
}

pub fn getInt(def: *const pg.DefElem) c_int {
    var int_val: c_int = undefined;
    const is_parsed = pg.parse_int(pg.defGetString(@constCast(def)), &int_val, 0, null);
    if (!is_parsed) {
        elog.ErrorThrow(@src(), "option {s} must be an integer", .{def.defname});
    }
    return int_val;
}

pub fn getReal(def: *const pg.DefElem) f64 {
    var real_val: f64 = undefined;
    const is_parsed = pg.parse_real(pg.defGetString(@constCast(def)), &real_val, 0, null);
    if (!is_parsed) {
        elog.ErrorThrow(@src(), "option {s} must be a floating number", .{def.defname});
    }
    return real_val;
}

pub fn getOid(def: *const pg.DefElem) pg.Oid {
    var int_val: c_int = undefined;
    const is_parsed = pg.parse_int(pg.defGetString(@constCast(def)), &int_val, 0, null);
    if (!is_parsed) {
        elog.ErrorThrow(@src(), "option {s} must be an OID", .{def.defname});
    }
    if (int_val <= 0) {
        elog.ErrorThrow(@src(), "option {s} must be a valid OID", .{def.defname});
    }

    return @intCast(int_val);
}

pub fn validateBool(def: *const pg.DefElem, context: pg.Oid) void {
    _ = context;
    _ = getBool(def);
}

pub fn validateInt(def: *const pg.DefElem, context: pg.Oid) void {
    _ = context;
    _ = getInt(def);
}

pub fn validateIntPos(def: *const pg.DefElem, context: pg.Oid) void {
    _ = context;
    const i = getInt(def);
    if (i <= 0) {
        elog.ErrorThrow(@src(), "option {s} must greater than 0", .{def.defname});
    }
}

pub fn validateIntPos0(def: *const pg.DefElem, context: pg.Oid) void {
    _ = context;
    const i = getInt(def);
    if (i < 0) {
        elog.ErrorThrow(@src(), "option {s} must greater than or equal to 0", .{def.defname});
    }
}

pub fn validateReal(def: *const pg.DefElem, context: pg.Oid) void {
    _ = context;
    _ = getReal(def);
}

pub fn validateRealPos(def: *const pg.DefElem, context: pg.Oid) void {
    _ = context;
    const r = getReal(def);
    if (r <= 0) {
        elog.ErrorThrow(@src(), "option {s} must greater than 0", .{def.defname});
    }
}

pub fn validateRealPos0(def: *const pg.DefElem, context: pg.Oid) void {
    _ = context;
    const r = getReal(def);
    if (r < 0) {
        elog.ErrorThrow(@src(), "option {s} must greater than or equal to 0", .{def.defname});
    }
}

pub fn validateOid(def: *const pg.DefElem, context: pg.Oid) void {
    _ = context;
    _ = getOid(def);
}
