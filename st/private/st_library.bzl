"""Implementation of the st_library rule."""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("//st:providers.bzl", "StHeadersInfo", "StInfo", "create_st_compilation_context", "create_st_linking_context", "merge_st_infos")
load("//st:private/st_headers.bzl", "st_library_headers_gen")

def _st_library_impl(ctx):
    toolchain = ctx.toolchains["//st:toolchain_type"]
    compiler = toolchain.compiler

    dep_info = merge_st_infos([dep[StInfo] for dep in ctx.attr.deps])
    dep_objects = dep_info.linking_context.objects
    dep_interfaces = dep_info.compilation_context.interfaces

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
        inputs = depset(toolchain.compiler_runtime_files, transitive = [own_interfaces]),
        outputs = [out],
        mnemonic = "StCompile",
        progress_message = "Compiling ST library %{label}",
    )

    # Also export a plain CcInfo, wrapping the compiled object as a linkable
    # library, so non-ST rules (e.g. rust_test's deps) can depend on an
    # st_library directly, the same way they'd depend on a cc_library.
    cc_toolchain = find_cc_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    own_linking_context, _ = cc_common.create_linking_context_from_compilation_outputs(
        actions = ctx.actions,
        name = ctx.label.name,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        compilation_outputs = cc_common.create_compilation_outputs(
            objects = depset([out]),
            pic_objects = depset([out]),
        ),
        disallow_dynamic_library = True,
    )
    # Does not include plc's generated C headers -- this compile-only rule is
    # wrapped, along with st_library_headers_gen, by the public st_library
    # macro below, which bundles both into one target.
    exported_cc_info = cc_common.merge_cc_infos(cc_infos = [
        CcInfo(linking_context = own_linking_context),
    ] + [dep[CcInfo] for dep in ctx.attr.deps])

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
            ),
        ),
        exported_cc_info,
    ]

_st_library = rule(
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
        "_cc_toolchain": attr.label(default = Label("@rules_cc//cc:current_cc_toolchain")),
    },
    toolchains = ["//st:toolchain_type"] + use_cc_toolchain(),
    fragments = ["cpp"],
    doc = "Compiles ST sources into a relocatable object. Internal -- use the public st_library macro below.",
)

def _st_provider_fusion_impl(ctx):
    compile_target = ctx.attr.compile
    headers_target = ctx.attr.headers
    return [
        compile_target[DefaultInfo],
        compile_target[StInfo],
        headers_target[StHeadersInfo],
        cc_common.merge_cc_infos(cc_infos = [compile_target[CcInfo], headers_target[CcInfo]]),
    ]

_st_provider_fusion = rule(
    implementation = _st_provider_fusion_impl,
    attrs = {
        "compile": attr.label(mandatory = True, providers = [StInfo]),
        "headers": attr.label(mandatory = True, providers = [StHeadersInfo]),
    },
    doc = "Combines a compiled st_library with its generated headers into one target. Internal -- use the public st_library macro below.",
)

def st_library(name, srcs, hdrs = [], deps = [], visibility = None, **kwargs):
    """Compiles ST sources into a relocatable object, for linking into an st_binary/st_test or another st_library.

    Also generates and exports plc's C headers for srcs/hdrs, so a
    cc_test/cc_library depending on this target can #include the
    plc-generated .h directly instead of hand-declaring extern "C"
    signatures.

    Args:
        name: Name of this library.
        srcs: ST source files implementing this library. Also serves as the
            interface exposed to targets depending on this library.
        hdrs: Full type/declaration files (e.g. .dut TYPE definitions) with
            no implementation of their own. Compiled alongside srcs and
            re-exported to dependents, who see them via -i only (never
            recompiling them).
        deps: Other st_library targets this library's implementation calls into.
        visibility: Visibility of this library (the underlying compile-only/
            headers-only targets stay private regardless).
        **kwargs: Forwarded to the underlying compile-only rule.
    """
    compile_name = name + "_lib"
    _st_library(
        name = compile_name,
        srcs = srcs,
        hdrs = hdrs,
        deps = deps,
        visibility = ["//visibility:private"],
        **kwargs
    )
    headers_gen_name = name + "_headers"
    st_library_headers_gen(
        name = headers_gen_name,
        srcs = srcs,
        hdrs = hdrs,
        deps = deps,
        visibility = ["//visibility:private"],
    )
    _st_provider_fusion(
        name = name,
        compile = compile_name,
        headers = headers_gen_name,
        visibility = visibility,
    )
