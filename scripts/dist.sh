#!/usr/bin/env bash
# Builds the packages for one Ubuntu release into dist/<release>/. Works with
# the legacy builder too (CI's Docker has no buildx, so no --output): the
# image is built, and /out copied from a container that is never started.
#
#   scripts/dist.sh 24.04
set -euo pipefail
ubuntu=${1:?usage: dist.sh <ubuntu release>}
cd "$(dirname "$0")/.."
image=podman-ubuntu-build:$ubuntu

docker build --build-arg UBUNTU="$ubuntu" -t "$image" .
container=$(docker create "$image" none)
trap 'docker rm "$container" >/dev/null' EXIT
rm -rf "dist/$ubuntu"
mkdir -p "dist/$ubuntu"
docker cp "$container:/out/." "dist/$ubuntu/"
ls "dist/$ubuntu"
