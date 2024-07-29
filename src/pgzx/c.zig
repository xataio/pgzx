const std = @import("std");

const includes = @cImport({
    @cInclude("postgres.h");
    @cInclude("postgres_ext.h");

    @cInclude("fmgr.h");
    @cInclude("miscadmin.h");
    @cInclude("varatt.h");

    @cInclude("access/reloptions.h");
    @cInclude("access/tsmapi.h");
    @cInclude("access/xact.h");

    @cInclude("commands/event_trigger.h");

    @cInclude("catalog/binary_upgrade.h");
    @cInclude("catalog/catalog.h");
    @cInclude("catalog/catversion.h");
    @cInclude("catalog/dependency.h");
    @cInclude("catalog/genbki.h");
    @cInclude("catalog/heap.h");
    @cInclude("catalog/index.h");
    @cInclude("catalog/indexing.h");
    @cInclude("catalog/namespace.h");
    @cInclude("catalog/objectaccess.h");
    @cInclude("catalog/objectaddress.h");
    @cInclude("catalog/partition.h");
    @cInclude("catalog/pg_aggregate.h");
    @cInclude("catalog/pg_am.h");
    @cInclude("catalog/pg_amop.h");
    @cInclude("catalog/pg_amproc.h");
    @cInclude("catalog/pg_attrdef.h");
    @cInclude("catalog/pg_attribute.h");
    @cInclude("catalog/pg_auth_members.h");
    @cInclude("catalog/pg_authid.h");
    @cInclude("catalog/pg_cast.h");
    @cInclude("catalog/pg_class.h");
    @cInclude("catalog/pg_collation.h");
    @cInclude("catalog/pg_constraint.h");
    @cInclude("catalog/pg_control.h");
    @cInclude("catalog/pg_conversion.h");
    @cInclude("catalog/pg_database.h");
    @cInclude("catalog/pg_db_role_setting.h");
    @cInclude("catalog/pg_default_acl.h");
    @cInclude("catalog/pg_depend.h");
    @cInclude("catalog/pg_description.h");
    @cInclude("catalog/pg_enum.h");
    @cInclude("catalog/pg_event_trigger.h");
    @cInclude("catalog/pg_extension.h");
    @cInclude("catalog/pg_foreign_data_wrapper.h");
    @cInclude("catalog/pg_foreign_server.h");
    @cInclude("catalog/pg_foreign_table.h");
    @cInclude("catalog/pg_index.h");
    @cInclude("catalog/pg_inherits.h");
    @cInclude("catalog/pg_init_privs.h");
    @cInclude("catalog/pg_language.h");
    @cInclude("catalog/pg_largeobject.h");
    @cInclude("catalog/pg_largeobject_metadata.h");
    @cInclude("catalog/pg_namespace.h");
    @cInclude("catalog/pg_opclass.h");
    @cInclude("catalog/pg_operator.h");
    @cInclude("catalog/pg_opfamily.h");
    @cInclude("catalog/pg_parameter_acl.h");
    @cInclude("catalog/pg_partitioned_table.h");
    @cInclude("catalog/pg_policy.h");
    @cInclude("catalog/pg_proc.h");
    @cInclude("catalog/pg_publication.h");
    @cInclude("catalog/pg_publication_namespace.h");
    @cInclude("catalog/pg_publication_rel.h");
    @cInclude("catalog/pg_range.h");
    @cInclude("catalog/pg_replication_origin.h");
    @cInclude("catalog/pg_rewrite.h");
    @cInclude("catalog/pg_seclabel.h");
    @cInclude("catalog/pg_sequence.h");
    @cInclude("catalog/pg_shdepend.h");
    @cInclude("catalog/pg_shdescription.h");
    @cInclude("catalog/pg_shseclabel.h");
    @cInclude("catalog/pg_statistic.h");
    @cInclude("catalog/pg_statistic_ext.h");
    @cInclude("catalog/pg_statistic_ext_data.h");
    @cInclude("catalog/pg_subscription.h");
    @cInclude("catalog/pg_subscription_rel.h");
    @cInclude("catalog/pg_tablespace.h");
    @cInclude("catalog/pg_transform.h");
    @cInclude("catalog/pg_trigger.h");
    @cInclude("catalog/pg_ts_config.h");
    @cInclude("catalog/pg_ts_config_map.h");
    @cInclude("catalog/pg_ts_dict.h");
    @cInclude("catalog/pg_ts_parser.h");
    @cInclude("catalog/pg_ts_template.h");
    @cInclude("catalog/pg_type.h");
    @cInclude("catalog/pg_user_mapping.h");
    @cInclude("catalog/storage.h");
    @cInclude("catalog/storage_xlog.h");
    @cInclude("catalog/toasting.h");

    @cInclude("commands/defrem.h");

    @cInclude("foreign/foreign.h");
    @cInclude("foreign/fdwapi.h");

    @cInclude("executor/spi.h");
    @cInclude("executor/executor.h");
    @cInclude("windowapi.h");

    @cInclude("lib/ilist.h");

    @cInclude("nodes/bitmapset.h");
    @cInclude("nodes/execnodes.h");
    @cInclude("nodes/extensible.h");
    @cInclude("nodes/lockoptions.h");
    @cInclude("nodes/makefuncs.h");
    @cInclude("nodes/memnodes.h");
    @cInclude("nodes/miscnodes.h");
    @cInclude("nodes/multibitmapset.h");
    @cInclude("nodes/nodeFuncs.h");
    @cInclude("nodes/nodes.h");
    @cInclude("nodes/params.h");
    @cInclude("nodes/parsenodes.h");
    @cInclude("nodes/pathnodes.h");
    @cInclude("nodes/pg_list.h");
    @cInclude("nodes/plannodes.h");
    @cInclude("nodes/primnodes.h");
    @cInclude("nodes/print.h");
    @cInclude("nodes/queryjumble.h");
    @cInclude("nodes/readfuncs.h");
    @cInclude("nodes/replnodes.h");
    @cInclude("nodes/subscripting.h");
    @cInclude("nodes/supportnodes.h");
    @cInclude("nodes/tidbitmap.h");
    @cInclude("nodes/value.h");

    @cInclude("optimizer/appendinfo.h");
    @cInclude("optimizer/clauses.h");
    @cInclude("optimizer/cost.h");
    @cInclude("optimizer/geqo.h");
    @cInclude("optimizer/geqo_copy.h");
    @cInclude("optimizer/geqo_gene.h");
    @cInclude("optimizer/geqo_misc.h");
    @cInclude("optimizer/geqo_mutation.h");
    @cInclude("optimizer/geqo_pool.h");
    @cInclude("optimizer/geqo_random.h");
    @cInclude("optimizer/geqo_recombination.h");
    @cInclude("optimizer/geqo_selection.h");
    @cInclude("optimizer/inherit.h");
    @cInclude("optimizer/joininfo.h");
    @cInclude("optimizer/optimizer.h");
    @cInclude("optimizer/orclauses.h");
    @cInclude("optimizer/paramassign.h");
    @cInclude("optimizer/pathnode.h");
    @cInclude("optimizer/paths.h");
    @cInclude("optimizer/placeholder.h");
    @cInclude("optimizer/plancat.h");
    @cInclude("optimizer/planmain.h");
    @cInclude("optimizer/planner.h");
    @cInclude("optimizer/prep.h");
    @cInclude("optimizer/restrictinfo.h");
    @cInclude("optimizer/subselect.h");
    @cInclude("optimizer/tlist.h");

    @cInclude("parser/parser.h");
    @cInclude("parser/parse_utilcmd.h");

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
    @cInclude("utils/syscache.h");
    @cInclude("utils/lsyscache.h");
    @cInclude("utils/varlena.h");
    @cInclude("utils/regproc.h");
    @cInclude("utils/queryenvironment.h");

    @cInclude("tcop/cmdtag.h");
    @cInclude("tcop/dest.h");
    @cInclude("tcop/pquery.h");
    @cInclude("tcop/tcopprot.h");
    @cInclude("tcop/utility.h");

    // libpq support
    @cInclude("libpq-fe.h");
    @cInclude("libpq/libpq-be.h");
    @cInclude("libpqsrv.h");
});

pub usingnamespace includes;
