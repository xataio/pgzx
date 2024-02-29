#!/usr/bin/env bash

#set -x
set -o pipefail

test_pgzx() {
  rc=0
  run_unit_tests ./ || rc=1
  extension_drop pgzx_unit
  return $rc
}

test_char_count_zig() {
  extension_create char_count_zig
  trap "extension_drop char_count_zig" INT TERM

  rc=0
  run_regression_tests ./examples/char_count_zig || rc=1
  run_unit_tests ./examples/char_count_zig || rc=1

  extension_drop char_count_zig
  return $rc
}

test_pgaudit_zig() {
  run_unit_tests ./examples/pgaudit_zig
}


extension_build() {
  cwd=$(pwd)
  cd $1
  zig build -freference-trace -p $PG_HOME
  cd $cwd
}

extension_create() {
  echo "Create extension $1"
  psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS $1"
}

extension_drop() {
  echo "Drop extension $1"
  psql -U postgres -c "DROP EXTENSION IF EXISTS $1"
}

run_regression_tests() {
  echo "Run regression tests"
  rc=0

  cwd=$(pwd)
  cd $1
  zig build pg_regress --verbose || rc=1
  cd $cwd

  return $rc
}

run_unit_tests() {
  echo "Run unit tests"
  rc=0

  cwd=$(pwd)
  cd $1
  zig build -freference-trace -p $PG_HOME unit || rc=1
  cd $cwd

  return $rc
}

run_test_suites() {
  for t in "$@"; do
    echo "# Run $t"
    if ! $t; then
      return 1
    fi
  done
}

fail () {
  echo "$1" >&2
  exit 1
}

main() {
  echo "Build and install extension"
  eval $(pgenv)

  log_init_size=0;
  if [ -f $PG_CLUSTER_LOG_FILE ]; then
    log_init_size=$(stat -c %s $PG_CLUSTER_LOG_FILE)
  fi
  echo "Server log size: $log_init_size"

  extension_build ./examples/char_count_zig || fail "Failed to build char_count_zig"
  extension_build ./examples/pgaudit_zig || fail "Failed to build pgaudit_zig"

  echo "Start PostgreSQL"
  pgstart || fail "Failed to start PostgreSQL"
  trap pgstop TERM INT EXIT


  ok=true
  run_test_suites test_pgzx test_char_count_zig || ok=false

  if ! $ok; then
    echo "\n\nServer log:"

    log_size=$(stat -c %s $PG_CLUSTER_LOG_FILE)
    tail -c $((log_size - log_init_size)) $PG_CLUSTER_LOG_FILE
    fail "Regression tests failed"
  fi

  echo "Success!"
}

main
