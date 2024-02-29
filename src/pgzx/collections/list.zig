const c = @import("../c.zig");

// Wrapper for postgres lists.
//
// Postgres lists are internally implemented as a growing array of pointers. Similar
// to zigs ArrayList.
//
// All allocations are done one the current postgres memory context.
pub fn PointerListOf(comptime T: type) type {
    return struct {
        list: *c.List,

        const Iterator = IteratorOf(T);
        const ReverseIterator = ReverseIteratorOf(T);

        const Self = @This();

        pub fn create1(v: *T) Self {
            return Self.init(c.list_make1_impl(
                c.T_List,
                .{ .ptr_value = v },
            ));
        }

        pub fn create2(v1: *T, v2: *T) Self {
            return Self.init(c.list_make2_impl(
                c.T_List,
                .{ .ptr_value = v1 },
                .{ .ptr_value = v2 },
            ));
        }

        pub fn create3(v1: *T, v2: *T, v3: *T) Self {
            return Self.init(c.list_make3_impl(
                c.T_List,
                .{ .ptr_value = v1 },
                .{ .ptr_value = v2 },
                .{ .ptr_value = v3 },
            ));
        }

        pub fn create4(v1: *T, v2: *T, v3: *T, v4: *T) Self {
            return Self.init(c.list_make4_impl(
                c.T_List,
                .{ .ptr_value = v1 },
                .{ .ptr_value = v2 },
                .{ .ptr_value = v3 },
                .{ .ptr_value = v4 },
            ));
        }

        pub fn create5(v1: *T, v2: *T, v3: *T, v4: *T, v5: *T) Self {
            return Self.init(c.list_make5_impl(
                c.T_List,
                .{ .ptr_value = v1 },
                .{ .ptr_value = v2 },
                .{ .ptr_value = v3 },
                .{ .ptr_value = v4 },
                .{ .ptr_value = v5 },
            ));
        }

        pub fn init(l: *c.List) Self {
            if (l.type != c.T_List) {
                @panic("Expected a pointer list");
            }
            return Self{ .list = l };
        }

        pub fn deinit(self: Self) void {
            c.list_free(self.list);
        }

        pub fn deinitDeep(self: Self) void {
            c.list_free_deep(self.list);
        }

        pub fn rawList(self: Self) *c.List {
            return self.list;
        }

        pub fn copy(self: Self) Self {
            return Self.init(c.list_copy(self.list));
        }

        pub fn copyDeep(self: Self) Self {
            return Self.init(c.list_copy_deep(self.list));
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

        pub fn iter(self: Self) Iterator {
            return Iterator.init(self.list);
        }

        pub fn iterRev(self: Self) ReverseIterator {
            return ReverseIterator.init(self.list);
        }

        pub fn member(self: Self, value: *T) bool {
            return c.list_member(self.list, value);
        }

        pub fn memberPtr(self: Self, value: *T) bool {
            return c.list_member_ptr(self.list, value);
        }

        pub fn del(self: Self, value: *T) Self {
            return Self.init(c.list_delete(self.list, value));
        }

        pub fn delPtr(self: Self, value: *T) Self {
            return Self.init(c.list_delete_ptr(self.list, value));
        }

        pub fn createUnion(self: Self, other: *Self) Self {
            return Self.init(c.list_union(self.list, other.list));
        }

        pub fn createUnionPtr(self: Self, other: Self) Self {
            return Self.init(c.list_union_ptr(self.list, other.list));
        }

        pub fn createIntersection(self: Self, other: Self) Self {
            return Self.init(c.list_intersection(self.list, other.list));
        }

        pub fn createIntersectionPtr(self: Self, other: Self) Self {
            return Self.init(c.list_intersection_ptr(self.list, other.list));
        }

        pub fn createDifference(self: Self, other: Self) Self {
            return Self.init(c.list_difference(self.list, other.list));
        }

        pub fn createDifferencePtr(self: Self, other: Self) Self {
            return Self.init(c.list_difference_ptr(self.list, other.list));
        }

        pub fn append(self: Self, value: *T) Self {
            return Self.init(c.lappend(self.list, value));
        }

        pub fn concatUnique(self: Self, other: Self) Self {
            return Self.init(c.list_concat_unique(self.list, other.list));
        }

        pub fn concatUniquePtr(self: Self, other: Self) Self {
            return Self.init(c.list_concat_unique_ptr(self.list, other.list));
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

        pub fn init(l: *c.List) Self {
            if (l.type != c.T_List) {
                @panic("Expected a pointer list");
            }
            return Self{
                .list = l,
                .cell = fn_init(l),
            };
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

pub const PointerListTestSuite = struct {
    const std = @import("std");

    pub fn testIterator() !void {
        var elems = &[_]i32{ 1, 2, 3, 4, 5, 6 };
        var list = PointerListOf(i32).create5(
            @constCast(&elems[0]),
            @constCast(&elems[1]),
            @constCast(&elems[2]),
            @constCast(&elems[3]),
            @constCast(&elems[4]),
        );
        list = list.append(@constCast(&elems[5]));
        defer list.deinit();

        var it = list.iter();
        var i: i32 = 1;
        while (it.next()) |elem| {
            try std.testing.expect(i <= 6);
            try std.testing.expect(elem != null);
            try std.testing.expect(elem.?.* == i);
            i += 1;
        }
    }

    pub fn testIteratorRev() !void {
        var elems = &[_]i32{ 1, 2, 3, 4, 5, 6 };
        var list = PointerListOf(i32).create5(
            @constCast(&elems[0]),
            @constCast(&elems[1]),
            @constCast(&elems[2]),
            @constCast(&elems[3]),
            @constCast(&elems[4]),
        );
        list = list.append(@constCast(&elems[5]));
        defer list.deinit();

        var it = list.iterRev();
        var i: i32 = 6;
        while (it.next()) |elem| {
            try std.testing.expect(i > 0);
            try std.testing.expect(elem != null);
            try std.testing.expect(elem.?.* == i);
            i -= 1;
        }
    }
};
