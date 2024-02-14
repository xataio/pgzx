#!/usr/bin/env bash

set -e
set -o pipefail

echo "Build and install extension"

cd $PRJ_ROOT/examples/char_count_zig
zig build -freference-trace -p $PG_HOME

cd $PRJ_ROOT/examples/pgaudit_zig
zig build -freference-trace -p $PG_HOME

PGDATA=$PG_HOME/var/postgres/data

echo "Configure postgresql.conf"
echo "shared_preload_libraries = 'pg_audit_zig'" >> $PGDATA/postgresql.conf

echo "Start PostgreSQL"
pgstart
trap pgstop TERM INT EXIT

echo "Create extension"
psql -U postgres -c "CREATE EXTENSION char_count_zig"
psql -U postgres -c "CREATE EXTENSION pgaudit_zig"
psql -U postgres -c "SET pgaudit_zig.log_statement TO false"

echo "Run regression tests"
cd $PRJ_ROOT/examples/char_count_zig
zig build pg_regress --verbose

echo "Done"
