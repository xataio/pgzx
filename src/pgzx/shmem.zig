const c = @import("c.zig");

pub inline fn registerRequestHook(f: anytype) void {
    registerHook(f, &c.shmem_request_hook);
}

pub inline fn registerStartupHook(f: anytype) void {
    registerHook(f, &c.shmem_startup_hook);
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
    c.RequestAddinShmemSpace(@sizeOf(T));
}

pub inline fn createAndInit(comptime T: type) *T {
    // TODO: check that T implements init

    var found = false;
    const ptr = c.ShmemInitStruct(T.SHMEM_NAME, @sizeOf(T), &found);
    const shared_state: *T = @ptrCast(@alignCast(ptr));
    if (!found) {
        shared_state.init();
    }
    return shared_state;
}
