//! Postgres intrusive singly linked list support.

const std = @import("std");

const c = @import("../c.zig");

fn initNode() c.slist_node {
    return .{ .next = null };
}

pub fn SList(comptime T: type, comptime node_field: std.meta.FieldEnum(T)) type {
    return struct {
        const Self = @This();
        const Iterator = SListIter(T, node_field);

        usingnamespace SListMeta(T, node_field);

        head: c.slist_head,

        pub inline fn init() Self {
            var h = Self{ .head = undefined };
            c.slist_init(&h.head);
            return h;
        }

        pub inline fn initWith(init_head: c.slist_head) Self {
            return Self{ .head = init_head };
        }

        pub inline fn initFrom(init_node: *T) Self {
            var l = Self.init();
            l.head.head.next = Self.nodePtr(init_node);
            return l;
        }

        pub inline fn isEmpty(self: Self) bool {
            return c.slist_is_empty(&self.head);
        }

        pub inline fn pushHead(self: *Self, v: *T) void {
            c.slist_push_head(&self.head, Self.nodePtr(v));
        }

        pub inline fn popHead(self: *Self) ?*T {
            const node_ptr = c.slist_pop_head_node(&self.head);
            return Self.optNodeParentPtr(node_ptr);
        }

        pub inline fn headNode(self: Self) ?*T {
            const node_ptr = c.slist_head_node(@constCast(&self.head));
            return Self.optNodeParentPtr(node_ptr);
        }

        pub fn tail(self: Self) ?Self {
            if (self.isEmpty()) return null;

            const next_ptr = self.head.head.next.*.next;
            if (next_ptr == null) return null;

            var new_head: c.slist_head = undefined;
            new_head.head.next = next_ptr;
            return Self.initWith(new_head);
        }

        pub inline fn insertAfter(prev: *T, v: *T) void {
            c.slist_insert_after(Self.nodePtr(prev), Self.nodePtr(v));
        }

        pub inline fn hasNext(v: *T) bool {
            return Self.nodePtr(v).*.next != null;
        }

        pub inline fn next(v: *T) ?*T {
            const node_ptr = c.slist_next(Self.nodePtr(v));
            return Self.optNodeParentPtr(node_ptr);
        }

        pub inline fn iterator(self: *Self) Iterator {
            var i: c.slist_iter = undefined;
            i.cur = self.head.head.next;
            return .{ .iter = i };
        }
    };
}

pub fn SListIter(comptime T: type, comptime node_field: std.meta.FieldEnum(T)) type {
    return struct {
        const Self = @This();
        usingnamespace SListMeta(T, node_field);

        iter: c.slist_iter,

        pub inline fn next(self: *Self) ?*T {
            if (self.iter.cur == null) return null;
            const node_ptr = self.iter.cur;
            self.iter.cur = node_ptr.*.next;
            return if (node_ptr) |p| Self.nodeParentPtr(p) else null;
        }
    };
}

fn SListMeta(comptime T: type, comptime node_field: std.meta.FieldEnum(T)) type {
    return struct {
        const node = std.meta.fieldInfo(T, node_field).name;

        inline fn nodePtr(v: *T) *c.slist_node {
            return &@field(v, node);
        }

        inline fn nodeParentPtr(n: *c.slist_node) ?*T {
            return @fieldParentPtr(node, n);
        }

        inline fn optNodeParentPtr(n: ?*c.slist_node) ?*T {
            return if (n) |p| nodeParentPtr(p) else null;
        }
    };
}

pub const TestSuite_SList = struct {
    pub fn testEmpty() !void {
        const T = struct {
            value: u32,
            node: c.slist_node,
        };
        const MyList = SList(T, .node);

        var list = MyList.init();
        try std.testing.expect(list.isEmpty());

        var it = list.iterator();
        try std.testing.expect(it.next() == null);

        try std.testing.expect(list.headNode() == null);
        try std.testing.expect(list.tail() == null);
    }

    pub fn testPush() !void {
        const T = struct {
            value: u32,
            node: c.slist_node = .{ .next = null },
        };
        const MyListT = SList(T, .node);

        var values = [_]T{ .{ .value = 1 }, .{ .value = 2 }, .{ .value = 3 } };

        var list = MyListT.init();
        list.pushHead(&values[2]);
        list.pushHead(&values[1]);
        list.pushHead(&values[0]);

        var i: u32 = 1;
        var it = list.iterator();
        while (it.next()) |node| {
            try std.testing.expect(i <= 3);
            try std.testing.expect(node.*.value == i);
            i += 1;
        }
        try std.testing.expect(i == 4);

        try std.testing.expect(list.headNode().?.*.value == 1);
        try std.testing.expect(list.tail().?.headNode().?.*.value == 2);
    }

    pub fn testPop() !void {
        const T = struct {
            value: u32,
            node: c.slist_node = .{ .next = null },
        };
        const MyListT = SList(T, .node);

        var values = [_]T{ .{ .value = 1 }, .{ .value = 2 }, .{ .value = 3 } };

        var list = MyListT.init();
        list.pushHead(&values[2]);
        list.pushHead(&values[1]);
        list.pushHead(&values[0]);

        _ = list.popHead();

        var i: u32 = 2;
        var it = list.iterator();
        while (it.next()) |node| {
            try std.testing.expect(i <= 3);
            try std.testing.expect(node.*.value == i);
            i += 1;
        }
        try std.testing.expect(i == 4);
        try std.testing.expect(list.headNode().?.*.value == 2);
        try std.testing.expect(list.tail().?.headNode().?.*.value == 3);

        _ = list.popHead();
        _ = list.popHead();
        try std.testing.expect(list.isEmpty());

        it = list.iterator();
        try std.testing.expect(it.next() == null);

        try std.testing.expect(list.headNode() == null);
        try std.testing.expect(list.tail() == null);
    }
};
