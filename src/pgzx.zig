//! PostgreSQL extension module with utility functions for building PostgreSQL extensions with Zig.
//! During development we will mostly try to use the C API directly, but some functionality like
//! memory allocation and error handling need to be mapped to Zig.
//!

const std = @import("std");

// pub const Build = @import("pgzx/build.zig");

// Export common set of postgres headers.
pub const c = @import("pgzx/c.zig");

// Utility functions for working with the PostgreSQL C API.
pub const bgworker = @import("pgzx/bgworker.zig");
pub const elog = @import("pgzx/elog.zig");
pub const err = @import("pgzx/err.zig");
pub const fmgr = @import("pgzx/fmgr.zig");
pub const lwlock = @import("pgzx/lwlock.zig");
pub const mem = @import("pgzx/mem.zig");
pub const pq = @import("pgzx/pq.zig");
pub const shmem = @import("pgzx/shmem.zig");
pub const spi = @import("pgzx/spi.zig");
pub const str = @import("pgzx/str.zig");
pub const utils = @import("pgzx/utils.zig");
pub const intr = @import("pgzx/interrupts.zig");
pub const list = @import("pgzx/list.zig");

pub const guc = utils.guc;

pub const PGError = err.PGError;
pub const pgRethrow = err.pgRethrow;

pub const PG_MODULE_MAGIC = fmgr.PG_MODULE_MAGIC;
pub const PG_FUNCTION_V1 = fmgr.PG_FUNCTION_V1;
pub const PG_FUNCTION_INFO_V1 = fmgr.PG_FUNCTION_INFO_V1;

pub const PointerListOf = list.PointerListOf;
