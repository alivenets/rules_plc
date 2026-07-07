"""The st toolchain: wraps the rusty (plc) compiler executable."""

def _st_toolchain_impl(ctx):
    return [platform_common.ToolchainInfo(
        compiler = ctx.executable.compiler,
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
        "linker": attr.label(
            default = Label("@llvm_toolchain_llvm//:bin/clang"),
            allow_single_file = True,
            cfg = "exec",
            # plc detects "driver" linkers (cc/clang/gcc/...) by the basename of
            # this path and, when so, adds crt/libc automatically and honors
            # --fuse-ld. It must be the real clang binary -- toolchains_llvm's
            # cc_wrapper.sh shim defeats that name-based detection, which plc then
            # treats as a raw/direct linker and passes bare, causing clang to fall
            # back to a system `ld` search on $PATH -- empty in the sandboxed
            # action -- and fail.
            doc = "The clang binary forwarded to plc via --linker (used as a driver, not a direct linker).",
        ),
    },
)
