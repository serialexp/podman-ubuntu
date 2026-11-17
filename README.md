# podman-ubuntu

Podman 6 and the stack it needs, packaged for Ubuntu 24.04 (noble) and 26.04
(resolute) on amd64. Ubuntu ships Podman 4.9 and 5.7; this exists for
Podman 6's `rootless_port_forwarder = "pasta"`, which keeps client addresses
on rootless published ports (sorry-portainer's Caddy needs them).

The packages, all built from pinned upstream tags in [`versions.env`](versions.env):

| Package | Upstream |
|---|---|
| podman | containers/podman (podman, rootlessport, quadlet) |
| crun | containers/crun |
| conmon | containers/conmon |
| netavark | containers/netavark |
| aardvark-dns | containers/aardvark-dns |
| passt | passt (pasta and pesto, with their AppArmor profiles) |
| catatonit | openSUSE/catatonit |
| podman-compose | containers/podman-compose (24.04's 1.0.6 can't `up` a project with containers on Podman 6) |
| golang-github-containers-common | containers/container-libs `common/` (containers.conf, seccomp.json, policy.json, short names) |
| golang-github-containers-image | containers/container-libs `image/` (registries.conf) |
| containers-storage | containers/container-libs `storage/` (storage.conf only) |

Patches to upstream are in `patches/<component>/`, applied in order at build
time (passt: AppArmor lets Podman stop pasta; podman-compose: `up` fails, rather
than waits for ever, on a `service_healthy` dependency that is unhealthy, has no
healthcheck or has stopped). They use Ubuntu's package names and file layout, so they upgrade Ubuntu's own
packages in place, and versions `<upstream>-1000sp<REVISION>~ubuntu<release>`,
which sort above Ubuntu's even at the same upstream version (26.04's
catatonit is `0.2.1-2build1`). Binaries stay at `/usr/bin` so Ubuntu's AppArmor
`userns` profiles for podman and crun still apply.

## Building

Each Ubuntu release builds in its own container; the output, in
`dist/<release>/`, is the `.deb` files and a `SHA256SUMS-ubuntu<release>`:

```sh
scripts/dist.sh 24.04
scripts/dist.sh 26.04
```

`scripts/fetch.sh` refuses a tag that no longer resolves to its pinned
commit, and the Go and Rust toolchains are checked against their SHA-256.
The Check workflow builds and smoke-tests both releases on every push.

Smoke test, in a clean container (`fresh`), or over Ubuntu's Podman
(`upgrade`):

```sh
docker run --rm --privileged -v /var/lib/containers -v "$PWD/dist/24.04:/dist:ro" \
  -v "$PWD/scripts/smoke.sh:/smoke.sh:ro" ubuntu:24.04 /smoke.sh upgrade
```

The last check runs rootless Podman with `rootless_port_forwarder = "pasta"`
and asserts that a published port sees the client's address. The host's
AppArmor policy applies inside the container: a host with an older passt
installed confines the new pasta with its old profile, and the check fails
with `Permission denied` from pasta. CI sets `SMOKE_APPARMOR=1`, which loads
the packages' own profiles into the (throwaway) VM's kernel so the check runs
confined as on a real host; don't set it on a machine you care about.

## Releasing

1. Change `versions.env`. Bump `REVISION` for a packaging change; reset it
   to 1 for a new Podman version.
2. Commit, push, and tag `v<PODMAN_VERSION>-<REVISION>`.
3. Run the Release workflow with that tag. It builds both releases,
   smoke-tests them and publishes a Gothab release.
4. `scripts/pins.sh <tag>` prints the asset URLs and checksums for the hosts'
   rsansible variables.

Once Gothab has apt repositories (REQ-55 in serialexp/gothab), the workflow
publishes there instead and hosts use a sources entry.
