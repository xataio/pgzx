#!/usr/bin/env bash

set -e
set -o pipefail

echo "Build and install extension"

cd $PRJ_ROOT/examples/char_count_zig
zig build -freference-trace -p $PG_HOME

cd $PRJ_ROOT/examples/pgaudit_zig
zig build -freference-trace -p $PG_HOME

cluster_dir=$PG_HOME/var/postgres
PGDATA=$cluster_dir/data

echo "Start PostgreSQL"
pgstart
trap pgstop TERM INT EXIT

echo "Print server log"
cat $cluster_dir/log/server.log

echo "Create extension"
psql -U postgres -c "CREATE EXTENSION char_count_zig"
# psql -U postgres -c "CREATE EXTENSION pgaudit_zig"

echo "Run regression tests"
cd $PRJ_ROOT/examples/char_count_zig
zig build pg_regress --verbose

echo "Run unit Zig tests"
cd $PRJ_ROOT/examples/char_count_zig
zig build -freference-trace -p $PG_HOME unit

echo "Done"
