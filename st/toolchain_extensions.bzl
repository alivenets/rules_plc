"""Bzlmod module extension to register an LLVM toolchain for rules_plc consumers."""

load("@toolchains_llvm//toolchain:rules.bzl", "llvm_toolchain")

def _llvm_toolchain_extension_impl(module_ctx):
    for module in module_ctx.modules:
        if not module.is_root:
            fail("Only the root module can use the 'llvm' extension")

        for toolchain_attr in module.tags.toolchain:
            llvm_toolchain(
                name = toolchain_attr.name,
                llvm_version = toolchain_attr.llvm_version,
                llvm_versions = toolchain_attr.llvm_versions,
                stdlib = toolchain_attr.stdlib,
            )

    return module_ctx.extension_metadata(reproducible = True)

llvm = module_extension(
    implementation = _llvm_toolchain_extension_impl,
    tag_classes = {
        "toolchain": tag_class(
            attrs = {
                "name": attr.string(
                    doc = "Name of the generated LLVM toolchain and repository.",
                    default = "llvm_toolchain",
                ),
                "llvm_version": attr.string(
                    doc = "LLVM version to install. Either this or llvm_versions must be set.",
                ),
                "llvm_versions": attr.string_dict(
                    doc = "Mapping from target names to LLVM versions. Exactly one of llvm_version or llvm_versions must be set.",
                    default = {},
                ),
                "stdlib": attr.string_dict(
                    doc = "Mapping from C++ standard library names to the selected library.",
                    default = {},
                ),
            },
        ),
    },
)
