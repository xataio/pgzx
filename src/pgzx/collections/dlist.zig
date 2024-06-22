//! Postgres intrusive double linked list support.

const std = @import("std");
const pg = @import("pgzx_pgsys");

fn initNode() pg.dlist_node {
    return .{ .prev = null, .next = null };
}

pub fn DList(comptime T: type, comptime node_field: std.meta.FieldEnum(T)) type {
    return struct {
        const Self = @This();

        pub const Iterator = DListIter(T, node_field);
        pub const descr = DListDescr(T, node_field);

        list: pg.dlist_head,

        pub inline fn init() Self {
            return .{ .list = .{ .head = initNode() } };
        }

        inline fn ensureInit(self: *Self) void {
            if (self.list.head.next == null) {
                pg.dlist_init(&self.list);
            }
        }

        // Append all elements from `other` to the end of `self`.
        //
        // This clears the `other` list.
        pub inline fn appendFrom(self: *Self, other: *Self) void {
            self.appendFromDList(&other.list);
        }

        // Append all elements from `other` to the end of `self`.
        //
        // This clears the `other` list.
        //
        // Safety:
        //
        // The elemenst in `other` must be of type T and the same member node
        // must have been used to insert the elements into `other`.
        //
        pub inline fn appendFromDList(self: *Self, other: *pg.dlist_head) void {
            appendDList(&self.list, other);
        }

        // Append all list elements to the end of `other`.
        //
        // This clears the current list.
        //
        // Safety:
        //
        // The `other` list must be compatible with the current list. The
        // element type and the node members must match the type of Self.
        pub inline fn appendToDList(self: *const Self, other: *pg.dlist_head) void {
            appendDList(other, &self.list);
        }

        pub inline fn appendFromSlice(self: *Self, slice: []T) void {
            if (slice.len == 0) {
                return;
            }
            self.ensureInit();

            for (slice) |*elem| {
                self.pushTail(elem);
            }
        }

        pub inline fn rawList(self: *Self) *pg.dlist_head {
            return &self.list;
        }

        pub inline fn count(self: *const Self) usize {
            var n: usize = 0;
            var it = self.iterator();
            while (it.next() != null) : (n += 1) {}
            return n;
        }

        pub inline fn isEmpty(self: *const Self) bool {
            return pg.dlist_is_empty(&self.list);
        }

        pub inline fn headNode(self: *const Self) *T {
            if (self.isEmpty()) {
                @panic("headNode on empty list");
            }
            const node = pg.dlist_head_node(@constCast(&self.list));
            return descr.nodeParentPtr(node.?);
        }

        pub inline fn tailNode(self: *const Self) *T {
            if (self.isEmpty()) {
                @panic("tailNode on empty list");
            }
            const node = pg.dlist_tail_node(@constCast(&self.list));
            return descr.nodeParentPtr(node.?);
        }

        pub inline fn pushHead(self: *Self, node: *T) void {
            pg.dlist_push_head(&self.list, descr.nodePtr(node));
        }

        pub inline fn pushTail(self: *Self, node: *T) void {
            pg.dlist_push_tail(&self.list, descr.nodePtr(node));
        }

        pub inline fn popHead(self: *Self) *T {
            if (self.isEmpty()) {
                @panic("popHead on empty list");
            }
            return descr.nodeParentPtr(pg.dlist_pop_head_node(&self.list));
        }

        pub inline fn popTail(self: *Self) *T {
            if (self.isEmpty()) {
                @panic("popTail on empty list");
            }
            const tail = pg.dlist_tail_node(&self.list);
            pg.dlist_delete(tail);
            return descr.nodeParentPtr(tail.?);
        }

        pub inline fn moveHead(self: *Self, node: *T) void {
            pg.dlist_move_head(&self.list, descr.nodePtr(node));
        }

        pub inline fn moveTail(self: *Self, node: *T) void {
            pg.dlist_move_tail(&self.list, descr.nodePtr(node));
        }

        pub inline fn nextNode(self: *const Self, node: *T) *T {
            return descr.nodeParentPtr(pg.dlist_next_node(&self.list, descr.nodePtr(node)));
        }

        pub inline fn prevNode(self: *const Self, node: *T) *T {
            return descr.nodeParentPtr(pg.dlist_prev_node(&self.list, descr.nodePtr(node)));
        }

        pub inline fn iterator(self: *const Self) Iterator {
            return Iterator.init(&self.list);
        }

        pub inline fn insertAfter(node: *T, new_node: *T) void {
            pg.dlist_insert_after(descr.nodePtr(node), descr.nodePtr(new_node));
        }

        pub inline fn insertBefore(node: *T, new_node: *T) void {
            pg.dlist_insert_before(descr.nodePtr(node), descr.nodePtr(new_node));
        }

        pub inline fn delete(node: *T) void {
            pg.dlist_delete(descr.nodePtr(node));
        }

        pub inline fn deleteThorougly(node: *T) void {
            pg.dlist_delete_thoroughly(descr.nodePtr(node));
        }

        pub inline fn isDetached(node: *T) bool {
            return pg.dlist_is_detached(descr.nodePtr(node));
        }
    };
}

fn appendDList(to: *pg.dlist_head, from: *pg.dlist_head) void {
    if (pg.dlist_is_empty(from)) {
        return;
    }
    if (to.head.next == null) {
        pg.dlist_init(to);
    }

    to.*.head.prev.*.next = from.*.head.next;
    from.*.head.next.*.prev = to.*.head.prev;
    from.*.head.prev.*.next = &to.*.head;
    to.*.head.prev = from.*.head.prev;

    pg.dlist_init(from);
}

fn DListIter(comptime T: type, comptime node_field: std.meta.FieldEnum(T)) type {
    return struct {
        const Self = @This();

        const descr = DListDescr(T, node_field);

        iter: pg.dlist_iter,

        pub fn init(list: *const pg.dlist_head) Self {
            const end = &list.head;
            return .{
                .iter = .{
                    .end = @constCast(end),
                    .cur = @constCast(if (list.head.next) |n| n else end),
                },
            };
        }

        pub inline fn next(self: *Self) ?*T {
            if (self.iter.cur == self.iter.end) {
                return null;
            }

            const node = descr.nodeParentPtr(self.iter.cur);
            self.iter.cur = self.iter.cur.*.next;
            return node;
        }
    };
}

pub fn DListDescr(comptime T: type, comptime node_field: std.meta.FieldEnum(T)) type {
    return struct {
        const node = std.meta.fieldInfo(T, node_field).name;

        pub inline fn nodePtr(v: *T) *pg.dlist_node {
            return &@field(v, node);
        }

        pub inline fn nodeParentPtr(n: *pg.dlist_node) *T {
            return @fieldParentPtr(node, n);
        }

        pub inline fn optNodeParentPtr(n: ?*pg.dlist_node) ?*T {
            return if (n) |p| nodeParentPtr(p) else null;
        }
    };
}

pub const TestSuite_DList = struct {
    const TList = DList(T, .node);

    const T = struct {
        value: u32,
        node: pg.dlist_node = initNode(),
    };

    pub fn testEmpty() !void {
        var list = TList.init();
        try std.testing.expectEqual(true, list.isEmpty());

        var it = list.iterator();
        while (it.next()) |n| {
            _ = n;
            std.log.info("iterating over empty list", .{});
            try std.testing.expect(false);
        }
    }

    pub fn testAppendFrom() !void {
        var list1 = TList.init();
        var list2 = TList.init();
        var elems = [_]T{ .{ .value = 1 }, .{ .value = 2 }, .{ .value = 3 } };
        list2.appendFromSlice(elems[0..]);
        list1.appendFrom(&list2);

        try std.testing.expectEqual(false, list1.isEmpty());
        try std.testing.expectEqual(true, list2.isEmpty());
        try std.testing.expectEqual(1, list1.headNode().*.value);
        try std.testing.expectEqual(3, list1.tailNode().*.value);

        try std.testing.expectEqual(3, list1.count());
        try std.testing.expectEqual(0, list2.count());
    }

    pub fn testPushTail() !void {
        var list = TList.init();
        var elems = [_]T{ .{ .value = 1 }, .{ .value = 2 }, .{ .value = 3 } };
        list.pushTail(&elems[0]);
        list.pushTail(&elems[1]);
        list.pushTail(&elems[2]);

        try std.testing.expectEqual(false, list.isEmpty());
        try std.testing.expectEqual(list.headNode().*.value, 1);
        try std.testing.expectEqual(list.tailNode().*.value, 3);
        try std.testing.expectEqual(3, list.count());

        var i: u32 = 0;
        var it = list.iterator();
        while (it.next()) |n| {
            i += 1;
            try std.testing.expect(i <= 3);
            try std.testing.expectEqual(i, n.value);
        }
        try std.testing.expectEqual(3, i);
    }

    pub fn testPushHead() !void {
        var list = TList.init();
        var elems = [_]T{ .{ .value = 1 }, .{ .value = 2 }, .{ .value = 3 } };
        list.pushHead(&elems[0]);
        list.pushHead(&elems[1]);
        list.pushHead(&elems[2]);

        try std.testing.expectEqual(false, list.isEmpty());
        try std.testing.expectEqual(list.headNode().*.value, 3);
        try std.testing.expectEqual(list.tailNode().*.value, 1);
        try std.testing.expectEqual(3, list.count());

        var i: u32 = 3;
        var it = list.iterator();
        while (it.next()) |n| {
            try std.testing.expect(i >= 1);
            try std.testing.expectEqual(i, n.value);
            i -= 1;
        }
        try std.testing.expectEqual(0, i);
    }

    pub fn testPopHead() !void {
        var list = TList.init();
        var elems = [_]T{ .{ .value = 1 }, .{ .value = 2 }, .{ .value = 3 } };
        list.appendFromSlice(elems[0..]);

        const oldHead = list.popHead();
        try std.testing.expectEqual(1, oldHead.value);
        try std.testing.expectEqual(2, list.count());
        try std.testing.expectEqual(2, list.headNode().*.value);
        try std.testing.expectEqual(3, list.tailNode().*.value);
    }

    pub fn testPopTail() !void {
        var list = TList.init();
        var elems = [_]T{ .{ .value = 1 }, .{ .value = 2 }, .{ .value = 3 } };
        list.appendFromSlice(elems[0..]);

        const oldTail = list.popTail();
        try std.testing.expectEqual(3, oldTail.value);
        try std.testing.expectEqual(2, list.count());
        try std.testing.expectEqual(1, list.headNode().*.value);
        try std.testing.expectEqual(2, list.tailNode().*.value);
    }

    pub fn testMoveHead() !void {
        var list = TList.init();
        var elems = [_]T{ .{ .value = 1 }, .{ .value = 2 }, .{ .value = 3 } };
        list.appendFromSlice(elems[0..]);

        list.moveHead(list.tailNode());
        try std.testing.expectEqual(3, list.headNode().*.value);
        try std.testing.expectEqual(2, list.tailNode().*.value);
        try std.testing.expectEqual(3, list.count());
    }

    pub fn testMoveTail() !void {
        var list = TList.init();
        var elems = [_]T{ .{ .value = 1 }, .{ .value = 2 }, .{ .value = 3 } };
        list.appendFromSlice(elems[0..]);

        list.moveTail(list.headNode());
        try std.testing.expectEqual(2, list.headNode().*.value);
        try std.testing.expectEqual(1, list.tailNode().*.value);
        try std.testing.expectEqual(3, list.count());
    }

    pub fn testDelete() !void {
        var list = TList.init();
        var elems = [_]T{ .{ .value = 1 }, .{ .value = 2 }, .{ .value = 3 } };
        list.appendFromSlice(elems[0..]);

        TList.deleteThorougly(&elems[1]);
        try std.testing.expectEqual(2, list.count());
        try std.testing.expectEqual(elems[1].node.next, null);
        try std.testing.expectEqual(elems[1].node.prev, null);
    }
};
