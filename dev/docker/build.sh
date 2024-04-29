#!/usr/bin/env bash

set -e
set -x

IMAGE_NAME=pgzx
IMAGE_TAG=latest

SCRIPT_DIR=$(
	cd "$(dirname "$0")"
	pwd
)
PRJ_ROOT=${PRJ_ROOT:-$(realpath "$SCRIPT_DIR/../..")}
DOCKERFILE=${DOCKERFILE:-"$PRJ_ROOT/dev/docker/Dockerfile"}

cd "$PRJ_ROOT"
docker build -t "$IMAGE_NAME:$IMAGE_TAG" -f "$DOCKERFILE" .
