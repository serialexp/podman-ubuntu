#!/usr/bin/env bash
# Installs the pinned Go and Rust toolchains into /opt.
. /build/scripts/common.sh

cd /tmp
curl -fsSLo go.tar.gz "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
echo "$GO_SHA256  go.tar.gz" | sha256sum -c -
tar -C /opt -xzf go.tar.gz
rm go.tar.gz

rust="rust-${RUST_VERSION}-x86_64-unknown-linux-gnu"
curl -fsSLo rust.tar.xz "https://static.rust-lang.org/dist/${rust}.tar.xz"
echo "$RUST_SHA256  rust.tar.xz" | sha256sum -c -
tar -xJf rust.tar.xz
"./${rust}/install.sh" --prefix=/opt/rust \
  --components=rustc,cargo,rust-std-x86_64-unknown-linux-gnu >/dev/null
rm -rf rust.tar.xz "$rust"

/opt/go/bin/go version
/opt/rust/bin/rustc --version
