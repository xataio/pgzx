#!/usr/bin/env bash

#set -x
set -o pipefail

EXTENSION_NAME=pgaudit_zig

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

unit_tests() {
	echo "Run unit tests: $EXTENSION_NAME"
	zig build -freference-trace -p "$PG_HOME" unit || return 1
}

all() {
	build && create_extension && unit_tests && extension_drop
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
  unit_tests - run unit tests
  help - show this help message
EOF

case $command in
	all) all ;;
	build) build ;;
	create_extension) create_extension ;;
	extension_drop) extension_drop ;;
	unit_tests) unit_tests ;;
	help) echo "$HELP" ;;
	*) echo "$HELP" ;;
esac
