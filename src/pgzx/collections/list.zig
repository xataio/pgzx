const c = @import("../c.zig");

// Wrapper for postgres lists.
//
// Postgres lists are internally implemented as a growing array of pointers. Similar
// to zigs ArrayList.
//
// All allocations are done one the current postgres memory context.
pub fn PointerListOf(comptime T: type) type {
    return struct {
        const Self = @This();
        const Iterator = IteratorOf(T);
        const ReverseIterator = ReverseIteratorOf(T);

        list: ?*c.List,

        pub fn init() Self {
            return Self.initFrom(null);
        }

        pub fn initFrom(from: ?*c.List) Self {
            if (from) |l| {
                if (l.type != c.T_List) {
                    @panic("Expected a pointer list");
                }
            }
            return Self{ .list = from };
        }

        pub fn init1(v: *T) Self {
            return Self.initFrom(c.list_make1_impl(
                c.T_List,
                .{ .ptr_value = v },
            ));
        }

        pub fn init2(v1: *T, v2: *T) Self {
            return Self.initFrom(c.list_make2_impl(
                c.T_List,
                .{ .ptr_value = v1 },
                .{ .ptr_value = v2 },
            ));
        }

        pub fn init3(v1: *T, v2: *T, v3: *T) Self {
            return Self.initFrom(c.list_make3_impl(
                c.T_List,
                .{ .ptr_value = v1 },
                .{ .ptr_value = v2 },
                .{ .ptr_value = v3 },
            ));
        }

        pub fn init4(v1: *T, v2: *T, v3: *T, v4: *T) Self {
            return Self.initFrom(c.list_make4_impl(
                c.T_List,
                .{ .ptr_value = v1 },
                .{ .ptr_value = v2 },
                .{ .ptr_value = v3 },
                .{ .ptr_value = v4 },
            ));
        }

        pub fn init5(v1: *T, v2: *T, v3: *T, v4: *T, v5: *T) Self {
            return Self.initFrom(c.list_make5_impl(
                c.T_List,
                .{ .ptr_value = v1 },
                .{ .ptr_value = v2 },
                .{ .ptr_value = v3 },
                .{ .ptr_value = v4 },
                .{ .ptr_value = v5 },
            ));
        }

        pub fn deinit(self: Self) void {
            c.list_free(self.list);
        }

        pub fn deinitDeep(self: Self) void {
            c.list_free_deep(self.list);
        }

        pub fn rawList(self: Self) ?*c.List {
            return self.list;
        }

        pub fn copy(self: Self) Self {
            return Self.initFrom(c.list_copy(self.list));
        }

        pub fn copyDeep(self: Self) Self {
            return Self.initFrom(c.list_copy_deep(self.list));
        }

        pub fn sort(self: Self, cmp: fn (?*T, ?*T) c_int) void {
            c.list_sort(self.list, struct {
                fn c_cmp(a: [*c]c.ListCell, b: [*c]c.ListCell) c_int {
                    const ptrA: ?*T = @ptrCast(@alignCast(c.lfirst(a)));
                    const ptrB: ?*T = @ptrCast(@alignCast(c.lfirst(b)));
                    return cmp(ptrA, ptrB);
                }
            }.c_cmp);
        }

        pub fn len(self: Self) usize {
            return c.list_length(self.list);
        }

        pub fn iterator(self: Self) Iterator {
            return Iterator.init(self.list);
        }

        pub fn iteratorFrom(from: ?*c.List) Iterator {
            return Self.initFrom(from).iterator();
        }

        pub fn append(self: *Self, value: *T) void {
            var list: ?*c.List = self.list;
            list = c.lappend(list, value);
            self.list = list;
        }

        pub fn concatUnique(self: *Self, other: Self) void {
            self.list = c.list_concat_unique(self.list, other.list);
        }

        pub fn concatUniquePtr(self: *Self, other: Self) void {
            self.list = c.list_concat_unique_ptr(self.list, other.list);
        }

        pub fn reverseIterator(self: Self) ReverseIterator {
            return ReverseIterator.init(self.list);
        }

        pub fn reverseIteratorFrom(from: ?*c.List) ReverseIterator {
            return Self.initFrom(from).reverseIterator();
        }

        pub fn member(self: Self, value: *T) bool {
            return c.list_member(self.list, value);
        }

        pub fn memberPtr(self: Self, value: *T) bool {
            return c.list_member_ptr(self.list, value);
        }

        pub fn deleteNth(self: *Self, n: usize) void {
            if (n >= self.len()) {
                @panic("Index out of bounds");
            }
            self.list = c.list_delete_nth(self.list, @intCast(n));
        }

        pub fn deleteFirst(self: *Self) void {
            self.list = c.list_delete_first(self.list);
        }

        pub fn deleteFirstN(self: *Self, n: usize) void {
            self.list = c.list_delete_first_n(self.list, @intCast(n));
        }

        pub fn deleteLast(self: *Self) void {
            self.list = c.list_delete_last(self.list);
        }

        pub fn delete(self: *Self, value: *T) void {
            self.list = c.list_delete(self.list, value);
        }

        pub fn deletePointer(self: *Self, value: *T) void {
            self.list = c.list_delete_ptr(self.list, value);
        }

        pub fn createUnion(self: Self, other: *Self) Self {
            return Self.initFrom(c.list_union(self.list, other.list));
        }

        pub fn createUnionPtr(self: Self, other: Self) Self {
            return Self.initFrom(c.list_union_ptr(self.list, other.list));
        }

        pub fn createIntersection(self: Self, other: Self) Self {
            return Self.initFrom(c.list_intersection(self.list, other.list));
        }

        pub fn createIntersectionPtr(self: Self, other: Self) Self {
            return Self.initFrom(c.list_intersection_ptr(self.list, other.list));
        }

        pub fn createDifference(self: Self, other: Self) Self {
            return Self.initFrom(c.list_difference(self.list, other.list));
        }

        pub fn createDifferencePtr(self: Self, other: Self) Self {
            return Self.initFrom(c.list_difference_ptr(self.list, other.list));
        }
    };
}

pub fn IteratorOf(comptime T: type) type {
    return IteratorOfWith(T, c.list_head, c.lnext);
}

pub fn ReverseIteratorOf(comptime T: type) type {
    return IteratorOfWith(T, c.list_last_cell, lprev);
}

fn lprev(list: *c.List, cell: *c.ListCell) ?*c.ListCell {
    const idx = c.list_cell_number(list, cell);
    if (idx <= 0) {
        return null;
    }
    return c.list_nth_cell(list, idx - 1);
}

fn IteratorOfWith(comptime T: type, comptime fn_init: anytype, comptime fn_next: anytype) type {
    return struct {
        list: *c.List,
        cell: ?*c.ListCell,

        const Self = @This();

        pub fn init(list: ?*c.List) Self {
            if (list) |l| {
                if (l.type != c.T_List) {
                    @panic("Expected a pointer list");
                }
                return Self{ .list = l, .cell = fn_init(l) };
            } else {
                // Safety: The `list` element is not used when cell is null.
                return Self{ .list = undefined, .cell = null };
            }
        }

        pub fn next(self: *Self) ??*T {
            if (self.cell) |cell| {
                self.cell = fn_next(self.list, cell);
                const value: ?*T = @ptrCast(@alignCast(c.lfirst(cell)));
                return value;
            }
            return null;
        }
    };
}

pub const TestSuite_PointerList = struct {
    const std = @import("std");

    pub fn testIterator_emptyList() !void {
        var list = PointerListOf(i32).init();
        defer list.deinit();

        var it = list.iterator();
        try std.testing.expect(it.next() == null);
    }

    pub fn testIterator_forward() !void {
        var elems = &[_]i32{ 1, 2, 3, 4, 5, 6 };
        var list = PointerListOf(i32).init5(
            @constCast(&elems[0]),
            @constCast(&elems[1]),
            @constCast(&elems[2]),
            @constCast(&elems[3]),
            @constCast(&elems[4]),
        );
        list.append(@constCast(&elems[5]));
        defer list.deinit();

        var it = list.iterator();
        var i: i32 = 1;
        while (it.next()) |elem| {
            try std.testing.expect(i <= 6);
            try std.testing.expect(elem != null);
            try std.testing.expect(elem.?.* == i);
            i += 1;
        }
    }

    pub fn testIterator_reverse() !void {
        var elems = &[_]i32{ 1, 2, 3, 4, 5, 6 };
        var list = PointerListOf(i32).init5(
            @constCast(&elems[0]),
            @constCast(&elems[1]),
            @constCast(&elems[2]),
            @constCast(&elems[3]),
            @constCast(&elems[4]),
        );
        list.append(@constCast(&elems[5]));
        defer list.deinit();

        var it = list.reverseIterator();
        var i: i32 = 6;
        while (it.next()) |elem| {
            try std.testing.expect(i > 0);
            try std.testing.expect(elem != null);
            try std.testing.expect(elem.?.* == i);
            i -= 1;
        }
    }
};
