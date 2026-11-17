#!/usr/bin/env bash
# Installs the built packages into a clean Ubuntu container and checks that
# the stack fits together. Runs inside a privileged `ubuntu:<release>` with
# dist/<release> mounted at /dist and a volume at /var/lib/containers, since
# overlay storage can't sit on the outer container's overlayfs (see the
# workflow).
#
#   smoke.sh fresh     install on a system without Podman
#   smoke.sh upgrade   install Ubuntu's Podman and podman-compose first, then
#                      ours over them, as on a host that already has them
#
# With SMOKE_APPARMOR=1 it also installs apparmor, so the packages load their
# profiles, and the rootless check runs confined as on a real host. Profiles
# load into the kernel the container shares with its host, so set it only on
# a throwaway machine such as a CI VM.
set -euo pipefail
shopt -s inherit_errexit
export DEBIAN_FRONTEND=noninteractive

# The outer container's cgroup is the root of its namespace and holds its
# processes, so controllers can't be enabled for children (cgroup v2's
# no-internal-processes rule). Move everything into a leaf and delegate, as
# docker-in-docker does.
mkdir -p /sys/fs/cgroup/init
xargs -rn1 </sys/fs/cgroup/cgroup.procs >/sys/fs/cgroup/init/cgroup.procs 2>/dev/null || true
sed -e 's/ / +/g' -e 's/^/+/' </sys/fs/cgroup/cgroup.controllers >/sys/fs/cgroup/cgroup.subtree_control
apt-get update -qq
case "${1:-}" in
  fresh) ;;
  upgrade)
    apt-get install -y -qq podman podman-compose >/dev/null
    echo "Ubuntu's: $(podman --version), podman-compose $(dpkg-query -W -f='${Version}' podman-compose)"
    ;;
  *) echo "usage: smoke.sh fresh|upgrade" >&2; exit 2 ;;
esac
if [ "${SMOKE_APPARMOR:-}" = 1 ]; then
  mountpoint -q /sys/kernel/security || mount -t securityfs securityfs /sys/kernel/security
  apt-get install -y -qq apparmor >/dev/null
  aa-enabled
fi
apt-get install -y -qq /dist/*.deb curl iproute2 >/dev/null
if [ "${SMOKE_APPARMOR:-}" = 1 ]; then
  for profile in passt pasta pesto; do
    grep -q "^$profile (enforce)" /sys/kernel/security/apparmor/profiles
  done
  echo "AppArmor: passt, pasta and pesto profiles loaded"
fi
# AppArmor attaches profiles to the resolved path, so pasta must not be a
# symlink to passt (see build.sh).
for bin in pasta pasta.avx2; do
  [ ! -L "/usr/bin/$bin" ] || { echo "/usr/bin/$bin is a symlink" >&2; exit 1; }
done

podman --version
crun --version | head -1
conmon --version | head -1
/usr/lib/podman/netavark --version
/usr/lib/podman/aardvark-dns --version
pasta --version | head -1
pesto --version 2>&1 | head -1
catatonit --version 2>&1 | head -1
podman-compose --version | tail -1

# Every package must be ours: none of Ubuntu's may have won.
for pkg in podman crun conmon netavark aardvark-dns passt catatonit podman-compose \
  golang-github-containers-common golang-github-containers-image containers-storage; do
  version=$(dpkg-query -W -f='${Version}' "$pkg")
  case "$version" in
    *-1000sp*) echo "$pkg $version" ;;
    *) echo "$pkg is $version, not ours" >&2; exit 1 ;;
  esac
done

podman info --format '{{.Host.NetworkBackend}} {{.Host.OCIRuntime.Name}} {{.Version.Version}}'
podman info --format '{{.Host.NetworkBackend}}' | grep -qx netavark
podman info --format '{{.Host.OCIRuntime.Name}}' | grep -qx crun

# A container on a netavark bridge, with aardvark-dns resolving its name.
podman network create smoke >/dev/null
podman run -d --name web --network smoke docker.io/library/busybox:latest \
  httpd -f -p 8080 -h /etc >/dev/null
podman run --rm --network smoke docker.io/library/busybox:latest \
  wget -q -O /dev/null http://web:8080/hostname
podman rm -f -t 0 web >/dev/null
podman network rm smoke >/dev/null

# podman-compose against an existing project: a second `up` reads the config
# hash of the containers already there (1.0.6 does it with a template
# Podman 6 refuses), and --force-recreate replaces only what it names.
mkdir /compose
cat >/compose/compose.yaml <<'EOF'
services:
  web:
    image: docker.io/library/busybox:latest
    command: ["sh", "-c", "trap exit TERM; sleep 600 & wait"]
  side:
    image: docker.io/library/busybox:latest
    command: ["sh", "-c", "trap exit TERM; sleep 600 & wait"]
EOF
compose() { podman-compose -p smoke -f /compose/compose.yaml "$@" >/dev/null; }
id_of() { podman inspect --format '{{.Id}}' "smoke_$1_1"; }
compose up -d
web=$(id_of web) side=$(id_of side)
compose up -d
[ "$(id_of web)" = "$web" ] || { echo "a second up recreated web" >&2; exit 1; }
compose up -d --force-recreate web
[ "$(id_of web)" != "$web" ] || { echo "--force-recreate left web as it was" >&2; exit 1; }
[ "$(id_of side)" = "$side" ] || { echo "--force-recreate web recreated side" >&2; exit 1; }
[ "$(podman inspect --format '{{.State.Running}}' smoke_web_1)" = true ]
compose down
echo "podman-compose: up, up again, --force-recreate one service"

# Our patch: a service_healthy dependency that cannot become healthy (this
# one has no healthcheck) fails the dependent's start, where upstream waits
# for ever.
mkdir /compose-dep
cat >/compose-dep/compose.yaml <<'EOF'
services:
  db:
    image: docker.io/library/busybox:latest
    command: ["sh", "-c", "trap exit TERM; sleep 600 & wait"]
  app:
    image: docker.io/library/busybox:latest
    command: ["sh", "-c", "trap exit TERM; sleep 600 & wait"]
    depends_on:
      db:
        condition: service_healthy
EOF
dep_rc=0
dep_out=$(timeout 120 podman-compose -p smokedep -f /compose-dep/compose.yaml up -d 2>&1) || dep_rc=$?
[ "$dep_rc" -ne 124 ] || { echo "up waited for a dependency that cannot become healthy" >&2; exit 1; }
[ "$dep_rc" -ne 0 ] || { echo "up succeeded with a dependency that has no healthcheck" >&2; exit 1; }
case "$dep_out" in
  *"has no healthcheck"*) ;;
  *) echo "up failed, but not on the dependency: $dep_out" >&2; exit 1 ;;
esac
podman-compose -p smokedep -f /compose-dep/compose.yaml down >/dev/null
echo "podman-compose: an unhealthy dependency fails the start"

# Rootless, the reason this stack exists: with rootless_port_forwarder =
# "pasta", a port published from a bridge network sees the client's real
# address. The client must be off this host: pasta gives a connection from
# one of the host's own addresses a link-local source instead. So it is a
# network namespace of its own, on a veth pair.
ip netns add client
ip link add smoke0 type veth peer name smoke1 netns client
ip addr add 192.0.2.1/24 dev smoke0
ip link set smoke0 up
ip -n client addr add 192.0.2.2/24 dev smoke1
ip -n client link set smoke1 up
ip -n client link set lo up
# Its home, where rootless storage lives, is on the volume too.
home=/var/lib/containers/smoke
useradd -m -d "$home" smoke
uid=$(id -u smoke)
install -d -o smoke -g smoke -m 700 "/run/user/$uid"
# No systemd user session in here.
install -d -o smoke -g smoke "$home/.config" "$home/.config/containers"
install -o smoke -g smoke -m 644 /dev/stdin "$home/.config/containers/containers.conf" <<'EOF'
[engine]
cgroup_manager = "cgroupfs"
events_logger = "file"
EOF
as_smoke() {
  setpriv --reuid smoke --regid smoke --init-groups \
    env HOME="$home" XDG_RUNTIME_DIR="/run/user/$uid" "$@"
}
client_address() {
  as_smoke env CONTAINERS_CONF_OVERRIDE="$home/$1.conf" sh -ec '
    podman network create smoke >/dev/null
    podman run -d --name ip --network smoke -p 8081:8080 docker.io/library/busybox:latest sh -c "
      mkdir -p /www/cgi-bin
      printf \"#!/bin/sh\necho\necho \\\$REMOTE_ADDR\n\" >/www/cgi-bin/ip
      chmod +x /www/cgi-bin/ip
      exec httpd -f -p 8080 -h /www" >/dev/null'
  local seen
  # busybox httpd reports an IPv4 client as [::ffff:a.b.c.d].
  seen=$(ip netns exec client curl -fsS --retry 10 --retry-connrefused --retry-delay 1 \
    http://192.0.2.1:8081/cgi-bin/ip | tr -d '\r\n' | sed -e 's/^\[::ffff://' -e 's/\]$//')
  as_smoke env CONTAINERS_CONF_OVERRIDE="$home/$1.conf" sh -ec 'podman rm -f -t 0 ip >/dev/null; podman network rm smoke >/dev/null'
  echo "$seen"
}
for forwarder in rootlessport pasta; do
  printf '[network]\nrootless_port_forwarder = "%s"\n' "$forwarder" |
    install -o smoke -g smoke -m 644 /dev/stdin "$home/$forwarder.conf"
done
seen=$(client_address rootlessport)
echo "rootless, rootlessport: the container sees $seen"
seen=$(client_address pasta)
echo "rootless, pasta: the container sees $seen (client 192.0.2.2)"
[ "$seen" = 192.0.2.2 ]

echo "smoke: ok"
