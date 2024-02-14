#!/usr/bin/env bash

#set -e
#set -o pipefail

echo "Test test"
echo "Build and install extension"

cd $PRJ_ROOT/examples/char_count_zig
zig build -freference-trace -p $PG_HOME

cd $PRJ_ROOT/examples/pgaudit_zig
zig build -freference-trace -p $PG_HOME

cluster_dir=$PG_HOME/var/postgres
PGDATA=$cluster_dir/data

echo "Configure postgresql.conf"
echo "shared_preload_libraries = 'pg_audit_zig'" >> $PGDATA/postgresql.conf

echo "Start PostgreSQL"
pgstart || {
  echo "Failed to start PostgreSQL"
  echo "Printing server log:"
  cat $cluster_dir/log/server.log
  exit 1
}
trap pgstop TERM INT EXIT

echo "Print server log"
cat $cluster_dir/log/server.log

echo "Create extension"
psql -U postgres -c "CREATE EXTENSION char_count_zig"
psql -U postgres -c "CREATE EXTENSION pgaudit_zig"
psql -U postgres -c "SET pgaudit_zig.log_statement TO false"

echo "Run regression tests"
cd $PRJ_ROOT/examples/char_count_zig
zig build pg_regress --verbose

echo "Done"
