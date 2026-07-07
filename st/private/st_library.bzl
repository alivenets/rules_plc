"""Implementation of the st_library rule."""

load("//st:providers.bzl", "StInfo", "create_st_compilation_context", "create_st_linking_context", "merge_st_infos")

def _st_library_impl(ctx):
    compiler = ctx.toolchains["//st:toolchain_type"].compiler

    dep_info = merge_st_infos([dep[StInfo] for dep in ctx.attr.deps])
    dep_objects = dep_info.linking_context.objects
    dep_interfaces = dep_info.compilation_context.interfaces

    # c_deps are cc_library targets implementing this library's {external}
    # declarations natively; their CcInfo rides along in linking_context and
    # only actually gets linked in by the final st_binary/st_test.
    own_cc_infos = [dep[CcInfo] for dep in ctx.attr.c_deps]
    if dep_info.linking_context.cc_info != None:
        own_cc_infos.append(dep_info.linking_context.cc_info)
    cc_info = cc_common.merge_cc_infos(cc_infos = own_cc_infos) if own_cc_infos else None

    # hdrs are full declarations (e.g. .dut TYPE definitions) with no
    # implementation of their own. They're compiled alongside srcs so their
    # constructors are emitted exactly once, by the owning library; dependents
    # only ever see them via -i, never recompiling them.
    own_interfaces = depset(ctx.files.srcs + ctx.files.hdrs, transitive = [dep_interfaces])

    out = ctx.actions.declare_file(ctx.label.name + ".o")

    args = ctx.actions.args()
    args.add("-c")
    args.add_all(ctx.files.srcs)
    args.add_all(ctx.files.hdrs)
    args.add_all(dep_interfaces, before_each = "-i")
    args.add("-o", out)

    ctx.actions.run(
        executable = compiler,
        arguments = [args],
        inputs = own_interfaces,
        outputs = [out],
        mnemonic = "StCompile",
        progress_message = "Compiling ST library %{label}",
    )

    return [
        DefaultInfo(files = depset([out])),
        StInfo(
            compilation_context = create_st_compilation_context(
                # plc's -i ignores implementation bodies and only reads signatures, so
                # srcs can double as the interface consumers pass via -i -- no separate
                # hand-written interface file needed.
                interfaces = own_interfaces,
            ),
            linking_context = create_st_linking_context(
                objects = depset([out], transitive = [dep_objects]),
                cc_info = cc_info,
            ),
        ),
    ]

st_library = rule(
    implementation = _st_library_impl,
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = [".st"],
            doc = "ST source files implementing this library. Also serves as the interface exposed to targets depending on this library.",
        ),
        "hdrs": attr.label_list(
            allow_files = [".dut", ".st"],
            doc = "Full type/declaration files (e.g. .dut TYPE definitions) with no implementation of their own. Compiled alongside srcs and re-exported to dependents, who see them via -i only (never recompiling them).",
        ),
        "deps": attr.label_list(
            providers = [StInfo],
            doc = "Other st_library targets this library's implementation calls into.",
        ),
        "c_deps": attr.label_list(
            providers = [CcInfo],
            doc = "cc_library targets providing the native implementation of this library's {external} FUNCTION/FUNCTION_BLOCK declarations. Linked in by the final st_binary/st_test.",
        ),
    },
    toolchains = ["//st:toolchain_type"],
    doc = "Compiles ST sources into a relocatable object, for linking into an st_binary/st_test or another st_library.",
)
