#!/usr/bin/env bash

set -e
set -x

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
PRJ_ROOT=${PRJ_ROOT:-$(realpath "$SCRIPT_DIR/../..")}
DOCKERFILE=${DOCKERFILE:-"$PRJ_ROOT/dev/docker/Dockerfile"}

cd "$PRJ_ROOT"
docker build -t pgzx:latest -f "$DOCKERFILE" .
