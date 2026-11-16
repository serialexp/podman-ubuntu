#!/usr/bin/env bash
# Turns each /stage/<package> tree into /out/<package>_<version>_<arch>.deb,
# using packaging/<package>/: `control` (with @VERSION@ and @SHLIBS@),
# and optionally `conffiles` and maintainer scripts.
. /build/scripts/common.sh

declare -A upstream=(
  [podman]=$PODMAN_VERSION
  [crun]=$CRUN_VERSION
  [conmon]=$CONMON_VERSION
  [netavark]=$NETAVARK_VERSION
  [aardvark-dns]=$AARDVARK_DNS_VERSION
  [passt]=$PASST_VERSION
  [catatonit]=$CATATONIT_VERSION
  [podman-compose]=$PODMAN_COMPOSE_VERSION
  [golang-github-containers-common]=$COMMON_VERSION
  [golang-github-containers-image]=$IMAGE_VERSION
  [containers-storage]=$STORAGE_VERSION
)

# The Debian version for an upstream version, different per Ubuntu release.
# The revision's 1000 sorts it above Ubuntu's own packages of the same name
# even at the same upstream version (26.04 has catatonit 0.2.1-2build1),
# without an epoch, which could never be taken back.
deb_version() {
  printf '%s-1000sp%s~ubuntu%s' "$1" "$REVISION" "$UBUNTU"
}

# The library dependencies of a package's ELF files, as dpkg-shlibdeps
# computes them (it wants a debian/control to exist).
shlibs() {
  local root=$1 files
  mapfile -t files < <(find "$root" -type f -perm -u+x -exec sh -c 'head -c4 "$1" | grep -q ELF' _ {} \; -print)
  [ ${#files[@]} -eq 0 ] && return 0
  local work
  work=$(mktemp -d)
  mkdir "$work/debian"
  printf 'Source: shlibs\n\nPackage: shlibs\nArchitecture: any\n' >"$work/debian/control"
  (cd "$work" && dpkg-shlibdeps -O "${files[@]/#/-e}" 2>/dev/null) | sed -n 's/^shlibs:Depends=//p'
  rm -rf "$work"
}

mkdir -p "$OUT"
sums=()
for pkg in "${!upstream[@]}"; do
  root="$STAGE/$pkg"
  meta="/build/packaging/$pkg"
  [ -d "$root" ] || { echo "$pkg: nothing staged" >&2; exit 1; }
  version=$(deb_version "${upstream[$pkg]}")
  deps=$(shlibs "$root")
  mkdir -p "$root/DEBIAN"
  sed -e "s|@VERSION@|$version|" -e "s|@SHLIBS@|$deps|" \
      -e "s|@UPSTREAM@|${upstream[$pkg]}|" "$meta/control" |
    sed -e 's/^Depends: , /Depends: /' -e 's/, $//' -e '/^Depends: *$/d' >"$root/DEBIAN/control"
  echo "Installed-Size: $(du -sk --exclude=DEBIAN "$root" | cut -f1)" >>"$root/DEBIAN/control"
  for f in conffiles preinst postinst prerm postrm; do
    [ -f "$meta/$f" ] && install -m "$([ "$f" = conffiles ] && echo 644 || echo 755)" "$meta/$f" "$root/DEBIAN/$f"
  done
  arch=$(sed -n 's/^Architecture: //p' "$root/DEBIAN/control")
  deb="${pkg}_${version}_${arch}.deb"
  dpkg-deb --root-owner-group -Zxz --build "$root" "$OUT/$deb" >/dev/null
  echo "built $deb"
  cat "$root/DEBIAN/control"
done

(cd "$OUT" && sha256sum -- *.deb >"SHA256SUMS-ubuntu$UBUNTU")
cat "$OUT/SHA256SUMS-ubuntu$UBUNTU"
