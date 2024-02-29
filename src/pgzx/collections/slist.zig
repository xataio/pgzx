//! Postgres intrusive singly linked list support.

const std = @import("std");

const c = @import("../c.zig");

fn initNode() c.slist_node {
    return .{ .next = null };
}

pub fn SList(comptime T: type, comptime node_field: std.meta.FieldEnum(T)) type {
    return struct {
        head: c.slist_head,

        const Self = @This();
        usingnamespace SListMeta(T, node_field);

        const Iterator = SListIter(T, node_field);

        pub fn init() Self {
            var h = Self{};
            c.slist_init(&h.head);
            return h;
        }

        pub fn initWith(init_head: c.slist_head) Self {
            return Self{ .head = init_head };
        }

        pub fn initFrom(init_node: *T) Self {
            var l = Self.init();
            l.head.head.next = Self.nodePtr(init_node);
            return l;
        }

        pub fn isEmpty(self: *const Self) bool {
            return c.slist_empty(&self.head);
        }

        pub fn prepend(self: *Self, v: *T) void {
            c.slist_push_head(&self.head, Self.nodePtr(v));
        }

        pub fn popFront(self: *Self) ?*T {
            const node_ptr = c.slist_pop_head(&self.head);
            return Self.optNodeParentPtr(node_ptr);
        }

        pub fn head(self: *Self) ?*T {
            const node_ptr = c.slist_head_node(&self.head);
            return Self.optNodeParentPtr(node_ptr);
        }

        pub fn tail(self: *Self) ?*T {
            const node_ptr = c.slist_tail_node(&self.head);
            if (node_ptr == null) return null;

            var new_head: c.slit_head = undefined;
            new_head.head.next = node_ptr;
            return Self.initWith(new_head);
        }

        pub fn insertAfter(prev: *T, v: *T) void {
            c.slist_insert_after(Self.nodePtr(prev), Self.nodePtr(v));
        }

        pub fn hasNext(v: *T) bool {
            return Self.nodePtr(v).*.next != null;
        }

        pub fn next(v: *T) ?*T {
            const node_ptr = c.slist_next(Self.nodePtr(v));
            return Self.optNodeParentPtr(node_ptr);
        }

        pub fn iter(self: *Self) Iterator {
            var i: c.slist_iter = undefined;
            i.cur = Self.nodePtr(self.head.head.next);
            return .{ .iter = i };
        }
    };
}

pub fn SListIter(comptime T: type, comptime node_field: std.meta.FieldEnum(T)) type {
    return struct {
        const Self = @This();
        usingnamespace SListMeta(T, node_field);

        iter: c.slist_iter,

        pub fn next(self: *Self) ?*T {
            const node_ptr = c.slist_next(&self.node);
            return if (node_ptr) |p| Self.nodeParentPtr(p) else null;
        }
    };
}

fn SListMeta(comptime T: type, comptime node_field: std.meta.FieldEnum(T)) type {
    return struct {
        const node = @TypeOf(T).fieldInfo(node_field).name;

        fn nodePtr(v: *T) *c.slist_node {
            return &@field(v, node);
        }

        fn nodeParentPtr(n: *c.slist_node) ?*T {
            return @fieldParentPtr(T, node, n);
        }

        fn optNodeParentPtr(n: ?*c.slist_node) ?*T {
            return if (n) |p| nodeParentPtr(p) else null;
        }
    };
}

pub const TestSuite = struct {};
