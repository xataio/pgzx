const std = @import("std");

const pg = @import("pgzx_pgsys");

pub inline fn registerHooks(comptime T: anytype) void {
    if (std.meta.hasFn(T, "requestHook")) {
        registerRequestHook(T.requestHook);
    }
    if (std.meta.hasFn(T, "startupHook")) {
        registerStartupHook(T.startupHook);
    }
}

pub inline fn registerSharedState(comptime T: type, shared_state: **T) void {
    registerHooks(struct {
        pub fn requestHook() void {
            if (std.meta.hasFn(T, "shmemRequest")) {
                T.shmemRequest();
            } else {
                requestSpaceFor(T);
            }
        }

        pub fn startupHook() void {
            var found = false;
            const ptr = pg.ShmemInitStruct(T.SHMEM_NAME, @sizeOf(T), &found);
            shared_state.* = @ptrCast(@alignCast(ptr));
            if (!found) {
                if (std.meta.hasFn(T, "init")) {
                    shared_state.*.* = T.init();
                } else {
                    shared_state.*.* = std.mem.zeroes(T);
                }
            }
        }
    });
}

pub inline fn registerRequestHook(f: anytype) void {
    registerHook(f, &pg.shmem_request_hook);
}

pub inline fn registerStartupHook(f: anytype) void {
    registerHook(f, &pg.shmem_startup_hook);
}

inline fn registerHook(f: anytype, hook: anytype) void {
    const ctx = struct {
        var prev_hook: @TypeOf(hook.*) = undefined;
        fn hook_fn() callconv(.C) void {
            if (prev_hook) |prev| {
                prev();
            }
            f();
        }
    };

    ctx.prev_hook = hook.*;
    hook.* = ctx.hook_fn;
}

pub inline fn requestSpaceFor(comptime T: type) void {
    pg.RequestAddinShmemSpace(@sizeOf(T));
}

pub inline fn createAndZero(comptime T: type) *T {
    var found = false;
    const ptr = pg.ShmemInitStruct(T.SHMEM_NAME, @sizeOf(T), &found);
    const shared_state: *T = @ptrCast(@alignCast(ptr));
    if (!found) {
        shared_state.* = std.mem.zeroes(T);
    }
    return shared_state;
}

pub inline fn createAndInit(comptime T: type) *T {
    // TODO: check that T implements init

    var found = false;
    const ptr = pg.ShmemInitStruct(T.SHMEM_NAME, @sizeOf(T), &found);
    const shared_state: *T = @ptrCast(@alignCast(ptr));
    if (!found) {
        shared_state.init();
    }
    return shared_state;
}
