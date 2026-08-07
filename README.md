# rules_plc
Bazel module for ST code compilation.

## Setup

```python
bazel_dep(name = "rules_plc", version = "0.1.0")
```

`rules_plc` registers no default `//st:toolchain_type` toolchain, and
`st_toolchain`'s `linker` attr has no default -- you supply a `plc` compiler
binary and a C++ toolchain yourself. This isn't just a preference:
`toolchains_llvm`'s extension hard-fails for any non-root module, so
rules_plc genuinely can't supply a working default. See `examples/` (its own
nested module, a real consumer) for a complete working setup.

### Option A: a prebuilt release binary (recommended)

This repo publishes patched `plc` builds as GitHub Release archives (see
`plc_compiler/release.sh`): `plc-linux-<arch>.tar.gz`, bundling `plc` with
whatever runtime `.so` deps it actually needs (discovered via `ldd`, not a
hand-maintained list -- currently zlib/zstd/llvm_wrapper). It uses a
`$ORIGIN`-relative rpath, so they must be extracted alongside it.

In your `MODULE.bazel`:

```python
http_archive = use_repo_rule("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "plc_linux_x86_64",
    url = "https://github.com/alivenets/rules_plc/releases/download/0.1.5/plc-linux-x86_64.tar.gz",
    sha256 = "31177633ae225bf6774730db9afa043f0c8f2fc59372d5507f4859954c2e72b0",
    strip_prefix = "plc-linux-x86_64",
    build_file_content = """
package(default_visibility = ["//visibility:public"])
exports_files(["plc"])
filegroup(name = "runtime_libs", srcs = glob(["*.so"]))
""",
)
```

You also need a C++ toolchain for `st_toolchain`'s `linker` (the real clang
binary, not a wrapper script -- see its doc comment). `examples/MODULE.bazel`
sets one up via `toolchains_llvm`:

```python
bazel_dep(name = "toolchains_llvm", version = "1.8.0")

llvm = use_extension("@toolchains_llvm//toolchain/extensions:llvm.bzl", "llvm")
llvm.toolchain(
    name = "llvm_toolchain",
    llvm_version = "21.1.8",
    stdlib = {"": "stdc++"},
)
use_repo(llvm, "llvm_toolchain", "llvm_toolchain_llvm")
```

In a `BUILD.bazel` in your own repo (e.g. `//toolchains/plc/BUILD.bazel`):

```python
load("@rules_plc//st:defs.bzl", "st_toolchain")

st_toolchain(
    name = "plc_compiler",
    compiler = "@plc_linux_x86_64//:plc",
    compiler_runtime_files = ["@plc_linux_x86_64//:runtime_libs"],
    linker = "@llvm_toolchain_llvm//:bin/clang",
)

toolchain(
    name = "plc",
    toolchain = ":plc_compiler",
    toolchain_type = "@rules_plc//st:toolchain_type",
)
```

Then, in your `MODULE.bazel`:

```python
register_toolchains("//toolchains/plc:plc")
```

or `--extra_toolchains=//toolchains/plc:plc` in your own `.bazelrc` if you'd
rather it not propagate to your own downstream consumers.

For another CPU, add another `http_archive` (e.g. `plc-linux-aarch64.tar.gz`)
and `select()` between them on `@platforms//cpu:...` for `compiler`/
`compiler_runtime_files` -- `st_toolchain`'s attrs run in `cfg = "exec"`, so
`select()` resolves against the exec platform.

### Option B: build `plc` from source

`plc_compiler/` is a separate, standalone Bazel module (no dependency on
rules_plc) that builds a patched `plc` from source -- the source of truth
for Option A's release archives, kept out of rules_plc's own module graph.

Add it as a `bazel_dep` (`git_override`, or `local_path_override` if
vendored) and wire it up the same way as Option A:

```python
load("@rules_plc//st:defs.bzl", "st_toolchain")

st_toolchain(
    name = "plc_compiler",
    compiler = "@plc_compiler//third_party/rusty:plc",
    compiler_runtime_files = ["@plc_compiler//third_party/rusty:plc_runtime_libs"],
    linker = "@llvm_toolchain_llvm//:bin/clang",
)

toolchain(
    name = "plc_from_source",
    toolchain = ":plc_compiler",
    toolchain_type = "@rules_plc//st:toolchain_type",
)
```

then register it the same way as Option A.
