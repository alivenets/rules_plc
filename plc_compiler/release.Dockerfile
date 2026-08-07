# Build environment for release.sh: an older glibc (Ubuntu 22.04, glibc 2.35)
# than whatever the local dev machine happens to run, so the published
# plc-linux-x86_64.tar.gz doesn't end up requiring a newer glibc than
# necessary on target systems. Note this only bounds the floor so far --
# Rust's own std already hard-requires glibc >= 2.34 (pthread_create/dlopen
# etc. merged into libc.so as of glibc 2.34), regardless of build host.
#
# To release plc_compiler using this environment, from the repo root:
#
#   docker build -t plc-release -f plc_compiler/release.Dockerfile plc_compiler
#
#   docker run --rm -v "$(pwd)":/workspace -w /workspace \
#     -e GH_TOKEN="$(gh auth token)" \
#     plc-release \
#     bash -c '
#       git config --global --add safe.directory /workspace &&
#       plc_compiler/release.sh <tag>
#     '
#
# (the safe.directory config is needed because the container runs as root
# over a directory owned by your host user -- without it, `gh release
# create --generate-notes`'s changelog generation fails, and release.sh
# then can't tell an existing release from a new one).
#
# GH_TOKEN must have release-write access to the target repo; `gh auth
# token` reuses your host's existing `gh auth login` session.
#
# To speed up repeat runs (avoids re-downloading the LLVM/Rust toolchains
# and re-compiling ~9k actions from scratch each time), mount a
# repository cache and a disk cache and point Bazel at them via a
# container-local .bazelrc:
#
#   mkdir -p /tmp/plc-release-repo-cache /tmp/plc-release-disk-cache
#   printf 'common --repository_cache=/root/.cache/bazel-repo-cache\ncommon --disk_cache=/root/.cache/bazel-disk-cache\n' \
#     > /tmp/plc-release-bazelrc
#
#   docker run --rm -v "$(pwd)":/workspace \
#     -v /tmp/plc-release-repo-cache:/root/.cache/bazel-repo-cache \
#     -v /tmp/plc-release-disk-cache:/root/.cache/bazel-disk-cache \
#     -v /tmp/plc-release-bazelrc:/root/.bazelrc \
#     -w /workspace -e GH_TOKEN="$(gh auth token)" \
#     plc-release \
#     bash -c '
#       git config --global --add safe.directory /workspace &&
#       plc_compiler/release.sh <tag>
#     '
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    git \
    unzip \
    xz-utils \
    patch \
    python3 \
    gnupg \
    libc6-dev \
    g++ \
    libxml2 \
    zlib1g \
    libzstd1 \
    libtinfo6 \
    && rm -rf /var/lib/apt/lists/*

# gh CLI, for release.sh's `gh release create/upload`.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# bazelisk, pinned to this repo's .bazelversion (8.7.0).
RUN curl -fsSL -o /usr/local/bin/bazel https://github.com/bazelbuild/bazelisk/releases/download/v1.28.0/bazelisk-linux-amd64 \
    && chmod +x /usr/local/bin/bazel

WORKDIR /workspace
