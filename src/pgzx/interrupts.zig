const pg = @import("pgzx_pgsys");

const err = @import("err.zig");

/// Use Signal to create volatile variables that you can set in signal
/// handlers.
pub const Signal = Volatile(pg.sig_atomic_t);

/// Use SignalOf to create volatile variables based on existing C based
/// `volatile sig_atomic_t` variables.
///
/// IMPORTANT:
/// The zig translator does not translate support the C `volatile` keyword,
/// because you can only mark pointers as volatile. For this reason we MUST
/// wrap C based `volatile sig_atomic_t` variables.
pub const SignalOf = VolatilePtr(pg.sig_atomic_t);

pub fn VolatilePtr(comptime T: type) type {
    return struct {
        ptr: *volatile T = undefined,

        const Self = @This();

        pub fn create(p: *volatile T) Self {
            return .{ .ptr = p };
        }

        pub fn init(self: Self, p: *volatile T) void {
            self.ptr = p;
        }

        pub fn read(self: Self) T {
            return self.ptr.*;
        }

        pub fn set(self: Self, value: T) void {
            self.ptr.* = value;
        }

        pub fn isSet(self: Self) bool {
            return self.read() != 0;
        }

        pub fn clear(self: Self) void {
            self.set(0);
        }
    };
}

pub fn Volatile(comptime T: type) type {
    return struct {
        value: T = undefined,

        const Self = @This();

        pub fn new(value: T) Self {
            return .{ .value = value };
        }

        pub fn init(self: *Self, value: T) void {
            self.value = value;
        }

        pub fn read(self: *Self) T {
            const ptr: *volatile T = &self.value;
            return ptr.*;
        }

        pub fn set(self: *Self, value: T) void {
            const ptr: *volatile T = &self.value;
            ptr.* = value;
        }

        pub fn isSet(self: *Self) bool {
            return self.read() != 0;
        }

        pub fn clear(self: *Self) void {
            self.set(0);
        }
    };
}

pub const Pending = struct {
    // signals
    pub const Interrupt = SignalOf.create(&pg.InterruptPending);
    pub const QueryCancel = SignalOf.create(&pg.QueryCancelPending);
    pub const ProcDie = SignalOf.create(&pg.ProcDiePending);
    pub const CheckClientConnection = SignalOf.create(&pg.CheckClientConnectionPending);
    pub const ClientConnectionLost = SignalOf.create(&pg.ClientConnectionLost);
    pub const IdleInTransactionSessionTimeout = SignalOf.create(&pg.IdleInTransactionSessionTimeoutPending);
    pub const IdleSessionTimeout = SignalOf.create(&pg.IdleSessionTimeoutPending);
    pub const ProcSignalBarrier = SignalOf.create(&pg.ProcSignalBarrierPending);
    pub const LogMemoryContext = SignalOf.create(&pg.LogMemoryContextPending);
    pub const IdleStatsUpdateTimeout = SignalOf.create(&pg.IdleStatsUpdateTimeoutPending);

    // counts:
    pub const InterruptHoldoffCount = VolatilePtr(u32).create(&pg.InterruptHoldoffCount);
    pub const QueryCancelHoldoffCount = VolatilePtr(u32).create(&pg.QueryCancelHoldoffCount);
    pub const CritSectionCount = VolatilePtr(u32).create(&pg.CritSectionCount);
};

pub inline fn CheckForInterrupts() !void {
    if (Pending.Interrupt.read() != 0) {
        try err.wrap(pg.ProcessInterrupts, .{});
    }
}
