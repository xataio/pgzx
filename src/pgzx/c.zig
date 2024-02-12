const std = @import("std");

const includes = @cImport({
    @cInclude("postgres.h");
    @cInclude("postgres_ext.h");

    @cInclude("fmgr.h");
    @cInclude("miscadmin.h");
    @cInclude("varatt.h");

    @cInclude("executor/spi.h");
    @cInclude("executor/executor.h");

    @cInclude("parser/parser.h");

    @cInclude("postmaster/bgworker.h");
    @cInclude("postmaster/interrupt.h");
    @cInclude("port.h");

    @cInclude("commands/extension.h");

    @cInclude("storage/ipc.h");
    @cInclude("storage/proc.h");
    @cInclude("storage/latch.h");

    @cInclude("utils/builtins.h");
    @cInclude("utils/datum.h");
    @cInclude("utils/guc.h");
    @cInclude("utils/guc_hooks.h");
    @cInclude("utils/guc_tables.h");
    @cInclude("utils/memutils.h");
    @cInclude("utils/wait_event.h");
    @cInclude("utils/jsonb.h");
    @cInclude("utils/lsyscache.h");

    @cInclude("access/xact.h");

    // libpq support
    @cInclude("libpq-fe.h");
    @cInclude("libpq/libpq-be.h");
    @cInclude("libpqsrv.h");
});

pub usingnamespace includes;
