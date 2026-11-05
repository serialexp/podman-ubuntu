# Sourced by the build scripts.
set -euo pipefail

# shellcheck source=../versions.env
. /build/versions.env

SRC=/src
STAGE=/stage
OUT=/out

. /etc/os-release
UBUNTU="$VERSION_ID"

# Ubuntu's own packages install systemd files under /lib on 24.04 and
# /usr/lib on 26.04. Ours use the same paths: on a usr-merged system, a
# package upgrade that moves a file between the two aliases can make dpkg
# delete it.
case "$UBUNTU" in
  24.04) SYSTEMD_DIR=/lib/systemd ;;
  26.04) SYSTEMD_DIR=/usr/lib/systemd ;;
  *) echo "unsupported Ubuntu release $UBUNTU" >&2; exit 1 ;;
esac
