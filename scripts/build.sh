#!/usr/bin/env bash
# Builds one component and installs it into /stage/<package>, laid out as
# the package installs it.
. /build/scripts/common.sh

jobs=$(nproc)

case "$1" in
  podman)
    cd "$SRC/podman"
    make -j"$jobs" podman rootlessport quadlet
    make install.bin install.systemd install.completions \
      DESTDIR="$STAGE/podman" PREFIX=/usr ETCDIR=/etc \
      SYSTEMDDIR="$SYSTEMD_DIR/system" USERSYSTEMDDIR="$SYSTEMD_DIR/user" \
      SYSTEMDGENERATORSDIR="$SYSTEMD_DIR/system-generators" \
      USERSYSTEMDGENERATORSDIR="$SYSTEMD_DIR/user-generators"
    ;;
  crun)
    cd "$SRC/crun"
    ./autogen.sh
    ./configure --prefix=/usr
    # The default target, not `crun`: it generates git-version.h first.
    make -j"$jobs"
    install -D -m 755 crun "$STAGE/crun/usr/bin/crun"
    install -D -m 644 crun.1 "$STAGE/crun/usr/share/man/man1/crun.1"
    ;;
  conmon)
    cd "$SRC/conmon"
    make -j"$jobs" bin/conmon PREFIX=/usr
    install -D -m 755 bin/conmon "$STAGE/conmon/usr/bin/conmon"
    ;;
  netavark)
    cd "$SRC/netavark"
    cargo build --release --locked --bin netavark
    install -D -m 755 target/release/netavark "$STAGE/netavark/usr/lib/podman/netavark"
    ;;
  aardvark-dns)
    cd "$SRC/aardvark-dns"
    cargo build --release --locked
    install -D -m 755 target/release/aardvark-dns "$STAGE/aardvark-dns/usr/lib/podman/aardvark-dns"
    ;;
  passt)
    cd "$SRC/passt"
    make -j"$jobs" prefix=/usr VERSION="$PASST_TAG"
    make install DESTDIR="$STAGE/passt" prefix=/usr VERSION="$PASST_TAG"
    install -d "$STAGE/passt/etc/apparmor.d/abstractions"
    install -m 644 contrib/apparmor/abstractions/* "$STAGE/passt/etc/apparmor.d/abstractions/"
    install -m 644 contrib/apparmor/usr.bin.* "$STAGE/passt/etc/apparmor.d/"
    ;;
  catatonit)
    cd "$SRC/catatonit"
    ./autogen.sh
    ./configure --prefix=/usr
    make -j"$jobs"
    install -D -m 755 catatonit "$STAGE/catatonit/usr/bin/catatonit"
    install -d "$STAGE/catatonit/usr/libexec/podman"
    ln -s ../../bin/catatonit "$STAGE/catatonit/usr/libexec/podman/catatonit"
    ;;
  configs)
    # The same split as Ubuntu's packages, so these upgrade them in place.
    c="$STAGE/golang-github-containers-common"
    install -D -m 644 "$SRC/common/common/pkg/config/containers.conf" "$c/usr/share/containers/containers.conf"
    install -D -m 644 "$SRC/common/common/pkg/seccomp/seccomp.json" "$c/usr/share/containers/seccomp.json"
    install -D -m 644 "$SRC/common/image/default-policy.json" "$c/etc/containers/policy.json"
    install -D -m 644 "$SRC/shortnames/shortnames.conf" "$c/etc/containers/registries.conf.d/shortnames.conf"
    install -D -m 644 "$SRC/image/image/registries.conf" \
      "$STAGE/golang-github-containers-image/etc/containers/registries.conf"
    install -D -m 644 "$SRC/storage/storage/storage.conf" \
      "$STAGE/containers-storage/usr/share/containers/storage.conf"
    ;;
  *)
    echo "unknown component $1" >&2
    exit 1
    ;;
esac
