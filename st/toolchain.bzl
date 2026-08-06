"""The st toolchain: wraps the rusty (plc) compiler executable."""

def _st_toolchain_impl(ctx):
    return [platform_common.ToolchainInfo(
        compiler = ctx.executable.compiler,
        compiler_runtime_files = ctx.files.compiler_runtime_files,
        linker = ctx.file.linker,
    )]

st_toolchain = rule(
    implementation = _st_toolchain_impl,
    attrs = {
        "compiler": attr.label(
            mandatory = True,
            executable = True,
            cfg = "exec",
            allow_single_file = True,
            doc = "The rusty (plc) compiler executable.",
        ),
        "compiler_runtime_files": attr.label_list(
            allow_files = True,
            cfg = "exec",
            doc = "Extra files (e.g. shared libraries) that must sit alongside compiler for it to run. Only needed when compiler isn't itself a rule output with its own runfiles/data (e.g. a plain file fetched via http_archive).",
        ),
        "linker": attr.label(
            mandatory = True,
            allow_single_file = True,
            cfg = "exec",
            # Must be the real clang binary, not toolchains_llvm's
            # cc_wrapper.sh shim: plc detects "driver" linkers by basename
            # to auto-add crt/libc and honor --fuse-ld; the shim defeats
            # that, and clang falls back to a $PATH `ld` search that's
            # empty in the sandbox. No default: MODULE.bazel's own LLVM
            # toolchain is dev-only (see there), so a hardcoded default here
            # would break loading this rule for any consumer.
            doc = "The clang binary forwarded to plc via --linker (used as a driver, not a direct linker).",
        ),
    },
)
