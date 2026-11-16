# Builds the Podman stack's .deb packages for one Ubuntu release into /out
# of the final image; scripts/dist.sh copies them to dist/<release>.
#
# Each component is its own step, so a change to one rebuilds only it and
# what follows.
ARG UBUNTU=24.04

FROM ubuntu:${UBUNTU} AS build
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      autoconf automake build-essential ca-certificates curl dpkg-dev git \
      libapparmor-dev libcap-dev libglib2.0-dev libgpgme-dev libseccomp-dev \
      libsqlite3-dev libjson-c-dev libsubid-dev libsystemd-dev libtool \
      pkg-config protobuf-compiler python3 xz-utils \
    && rm -rf /var/lib/apt/lists/*

COPY versions.env /build/versions.env
COPY scripts/common.sh scripts/toolchains.sh /build/scripts/
RUN /build/scripts/toolchains.sh
ENV PATH=/opt/go/bin:/opt/rust/bin:/root/.cargo/bin:$PATH \
    GOTOOLCHAIN=local GOFLAGS=-mod=vendor CARGO_HOME=/root/.cargo

COPY scripts/fetch.sh /build/scripts/
RUN /build/scripts/fetch.sh

COPY scripts/build.sh /build/scripts/
COPY patches /build/patches
RUN /build/scripts/build.sh podman
RUN /build/scripts/build.sh crun
RUN /build/scripts/build.sh conmon
RUN /build/scripts/build.sh netavark
RUN /build/scripts/build.sh aardvark-dns
RUN /build/scripts/build.sh passt
RUN /build/scripts/build.sh catatonit
RUN /build/scripts/build.sh podman-compose
RUN /build/scripts/build.sh configs

COPY packaging /build/packaging
COPY scripts/package.sh /build/scripts/
RUN /build/scripts/package.sh

FROM scratch
COPY --from=build /out/ /out/
