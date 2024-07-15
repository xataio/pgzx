#!/usr/bin/env bash

#set -x
set -o pipefail

examples=(./examples/*)

fail() {
	echo "$1" >&2
	exit 1
}

build_example() {
	cwd=$(pwd)
	cd "$1" || return 1
	./ci/run.sh build || return 1
	cd "$cwd" || return 1
}

run_example() {
	cwd=$(pwd)
	cd "$1" || return 1
	./ci/run.sh || return 1
	cd "$cwd" || return 1
}

test_pgzx() {
	rc=0
	zig build -freference-trace -p "$PG_HOME" unit || rc=1
	psql -U postgres -c "DROP EXTENSION IF EXISTS pgzx_unit"
	return $rc
}

echo "Build and install extension"
eval "$(pgenv)"

log_init_size=0
if [ -f "$PG_CLUSTER_LOG_FILE" ]; then
	log_init_size=$(stat -c %s "$PG_CLUSTER_LOG_FILE")
fi
echo "Server log size: $log_init_size"

# build examples
echo "${examples[@]}"
build_jobs=()
for example in "${examples[@]}"; do
	echo -e "\n\nBuild example $example"
	build_example "$example" &
	build_jobs+=($!)
done
for job in "${build_jobs[@]}"; do
	wait "$job" || fail "Failed to build example"
done

echo -e "\n\nStart PostgreSQL"
pgstart || fail "Failed to start PostgreSQL"
trap pgstop TERM INT EXIT

echo -e "\n\nRun pgzx unit tests:"
test_pgzx || fail "Failed to run pgzx unit tests"

for example in "${examples[@]}"; do
	echo -e "\n\nRun example CI script $example"
	run_example "$example" || fail "Failed to run CI script for $example"
done

ok=true

if ! $ok; then
	printf "\n\nServer log:"

	log_size=$(stat -c %s "$PG_CLUSTER_LOG_FILE")
	tail -c $((log_size - log_init_size)) "$PG_CLUSTER_LOG_FILE"
	fail "Regression tests failed"
fi

echo "Success!"
