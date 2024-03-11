//! PostgreSQL extension module with utility functions for building PostgreSQL extensions with Zig.
//! During development we will mostly try to use the C API directly, but some functionality like
//! memory allocation and error handling need to be mapped to Zig.
//!

const std = @import("std");

// Export common set of postgres headers.
pub const c = @import("pgzx/c.zig");

// Utility functions for working with the PostgreSQL C API.
pub const bgworker = @import("pgzx/bgworker.zig");

pub const collections = @import("pgzx/collections.zig");
pub const PointerListOf = collections.list.PointerListOf;
pub const SList = collections.slist.SList;
pub const DList = collections.dlist.DList;
pub const HTab = collections.htab.HTab;
pub const HTabIter = collections.htab.HTabIter;
pub const StringHashTable = collections.htab.StringHashTable;
pub const KVHashTable = collections.htab.KVHashTable;

pub const elog = @import("pgzx/elog.zig");

pub const err = @import("pgzx/err.zig");
pub const PGError = err.PGError;
pub const pgRethrow = err.pgRethrow;

pub const fmgr = @import("pgzx/fmgr.zig");
pub const PG_MODULE_MAGIC = fmgr.PG_MODULE_MAGIC;
pub const PG_FUNCTION_V1 = fmgr.PG_FUNCTION_V1;
pub const PG_FUNCTION_INFO_V1 = fmgr.PG_FUNCTION_INFO_V1;

pub const lwlock = @import("pgzx/lwlock.zig");
pub const mem = @import("pgzx/mem.zig");
pub const pq = @import("pgzx/pq.zig");
pub const shmem = @import("pgzx/shmem.zig");
pub const spi = @import("pgzx/spi.zig");
pub const str = @import("pgzx/str.zig");
pub const utils = @import("pgzx/utils.zig");
pub const intr = @import("pgzx/interrupts.zig");
pub const testing = @import("pgzx/testing.zig");

pub const guc = utils.guc;
