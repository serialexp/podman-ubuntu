#!/usr/bin/env bash
# Clones every source at its pinned tag and checks the commit.
. /build/scripts/common.sh

fetch() {
  local name=$1 url=$2 tag=$3 commit=$4
  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$tag" "$url" "$SRC/$name"
  local head
  head=$(git -C "$SRC/$name" rev-parse HEAD)
  if [ "$head" != "$commit" ]; then
    echo "$name: tag $tag is $head, pinned $commit" >&2
    exit 1
  fi
}

mkdir -p "$SRC"
fetch podman https://github.com/containers/podman.git "$PODMAN_TAG" "$PODMAN_COMMIT"
fetch crun https://github.com/containers/crun.git "$CRUN_TAG" "$CRUN_COMMIT"
# crun's libocispec submodule (and its own submodules) are pinned by crun.
git -C "$SRC/crun" submodule update --quiet --init --recursive --depth 1
fetch conmon https://github.com/containers/conmon.git "$CONMON_TAG" "$CONMON_COMMIT"
fetch netavark https://github.com/containers/netavark.git "$NETAVARK_TAG" "$NETAVARK_COMMIT"
fetch aardvark-dns https://github.com/containers/aardvark-dns.git "$AARDVARK_DNS_TAG" "$AARDVARK_DNS_COMMIT"
fetch passt git://passt.top/passt "$PASST_TAG" "$PASST_COMMIT"
fetch catatonit https://github.com/openSUSE/catatonit.git "$CATATONIT_TAG" "$CATATONIT_COMMIT"
fetch common https://github.com/containers/container-libs.git "$COMMON_TAG" "$COMMON_COMMIT"
fetch image https://github.com/containers/container-libs.git "$IMAGE_TAG" "$IMAGE_COMMIT"
fetch storage https://github.com/containers/container-libs.git "$STORAGE_TAG" "$STORAGE_COMMIT"
fetch podman-compose https://github.com/containers/podman-compose.git "$PODMAN_COMPOSE_TAG" "$PODMAN_COMPOSE_COMMIT"
fetch shortnames https://github.com/containers/shortnames.git "$SHORTNAMES_TAG" "$SHORTNAMES_COMMIT"
