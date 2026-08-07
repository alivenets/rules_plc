# Build environment for release.sh: an older glibc (Ubuntu 22.04, glibc 2.35)
# than whatever the local dev machine happens to run, so the published
# plc-linux-x86_64.tar.gz doesn't end up requiring a newer glibc than
# necessary on target systems. Note this only bounds the floor so far --
# Rust's own std already hard-requires glibc >= 2.34 (pthread_create/dlopen
# etc. merged into libc.so as of glibc 2.34), regardless of build host.
#
# Usage, from the repo root:
#   docker build -t plc-release -f plc_compiler/release.Dockerfile plc_compiler
#   docker run --rm -v "$(pwd)":/workspace -w /workspace \
#     -e GH_TOKEN="$(gh auth token)" \
#     plc-release \
#     bash -c "git config --global --add safe.directory /workspace && plc_compiler/release.sh <tag>"
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
