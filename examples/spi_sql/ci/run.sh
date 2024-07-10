#!/usr/bin/env bash

#set -x
set -o pipefail

EXTENSION_NAME=char_count_zig

build() {
	echo "Build extension $EXTENSION_NAME"
	zig build -freference-trace -p "$PG_HOME" || return 1
}

create_extension() {
	echo "Create extension $EXTENSION_NAME"
	psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS $EXTENSION_NAME"
}

extension_drop() {
	echo "Drop extension $EXTENSION_NAME"
	psql -U postgres -c "DROP EXTENSION IF EXISTS $EXTENSION_NAME"
}

regression_tests() {
	echo "Run regression tests: $EXTENSION_NAME"
	zig build pg_regress --verbose || return 1
}

all() {
	build && create_extension && regression_tests && extension_drop
}

# optional command. Use all if not specified
command=${1:-all}

#shellcheck disable=SC1007
HELP= <<EOF
Usage: $0 [command]

commands (default 'all'):
  all - build nand run tests
  build - build and install extension
  create_extension - create extension
  extension_drop - drop extension
  regression_tests - run regression tests
  help - show this help message
EOF

case $command in
	all) all ;;
	build) build ;;
	create_extension) create_extension ;;
	extension_drop) extension_drop ;;
	regression_tests) regression_tests ;;
	unit_tests) unit_tests ;;
	help) echo "$HELP" ;;
	*) echo "$HELP" ;;
esac
