#!/usr/bin/env bash

set -x
set -o pipefail

test_char_count_zig() {
  echo "Create extension"
  extension_create char_count_zig
  trap "extension_drop char_count_zig" INT TERM

  echo "Run regression tests"
  run_regression_tests ./examples/char_count_zig

  echo "Run unit tests"
  run_unit_tests ./examples/char_count_zig

  extension_drop char_count_zig
}

test_pgaudit_zig() {
  echo "Run unit tests"
  run_unit_tests ./examples/pgaudit_zig
}

extension_build() {
  cwd=$(pwd)
  cd $1
  zig build -freference-trace -p $PG_HOME
  cd $cwd
}

extension_create() {
  psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS $1"
}

extension_drop() {
  psql -U postgres -c "DROP EXTENSION IF EXISTS $1"
}

run_regression_tests() {
  cwd=$(pwd)
  cd $1
  zig build pg_regress --verbose
  cd $cwd
}

run_unit_tests() {
  cwd=$(pwd)
  cd $1
  zig build -freference-trace -p $PG_HOME unit
  cd $cwd
}

fail () {
  echo "$1" >&2
  exit 1
}

main() {
  echo "Build and install extension"

  extension_build ./examples/char_count_zig || fail "Failed to build char_count_zig"
  extension_build ./examples/pgaudit_zig || fail "Failed to build pgaudit_zig"

  echo "Start PostgreSQL"
  pgstart || fail "Failed to start PostgreSQL"
  trap pgstop TERM INT EXIT

  ok=1
  test_char_count_zig || ok=0

  if [ $ok -eq 0 ]; then
    echo "\n\nServer log:"

    eval $(pgenv)
    cat $PG_CLUSTER_LOG_FILE
    fail "Regression tests failed"
  fi

  echo "Success!"
}

main
