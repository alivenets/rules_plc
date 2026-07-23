"""Implementation of the st_library rule."""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("//st:providers.bzl", "StInfo", "create_st_compilation_context", "create_st_linking_context", "merge_st_infos")
load("//st:private/headers.bzl", "generate_st_headers")

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

    # --generate-headers is a separate mode -- passing it alongside -c above
    # would skip compilation entirely rather than compile *and* emit headers.
    # With no -o, plc writes one .h per compiled module (named after that
    # module) into --header-output, instead of combining them into one file.
    headers_dir = generate_st_headers(ctx, compiler, ctx.files.srcs + ctx.files.hdrs, dep_interfaces, "st_library")

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
    # Also expose the generated headers on the CcInfo compilation context, so
    # a cc_test/cc_library depending on this st_library can #include the
    # plc-generated .h directly instead of hand-declaring extern "C"
    # signatures -- as e.g. "{package}/{name}_headers/{module}.h", relative
    # to the workspace/bin root, which every cc_* compile action already
    # searches by default. A bare `#include "{module}.h"` would risk silently
    # resolving to the wrong header if two libraries happen to compile
    # same-named modules, since `-I`/system_includes entries below aren't
    # package-scoped -- so that's deliberately not offered as an option here,
    # even though system_includes is what makes it possible. system_includes
    # (not quote_includes) is only for plc's own generated
    # `#include <dependencies.plc.h>`, which is always angle-bracket and
    # therefore needs a `-I`, not `-iquote`, search path; its content is an
    # identical no-op stub in every headers dir, so which copy an ambiguous
    # lookup picks doesn't matter.
    own_compilation_context = cc_common.create_compilation_context(
        headers = depset([headers_dir]),
        system_includes = depset([headers_dir.path]),
    )
    exported_cc_info = cc_common.merge_cc_infos(cc_infos = [
        CcInfo(compilation_context = own_compilation_context, linking_context = own_linking_context),
    ] + [dep[CcInfo] for dep in ctx.attr.deps] +
                                                            [dep[CcInfo] for dep in ctx.attr.c_deps])

    own_headers = depset([headers_dir], transitive = [dep_info.compilation_context.headers])

    return [
        DefaultInfo(files = depset([out])),
        StInfo(
            compilation_context = create_st_compilation_context(
                # plc's -i ignores implementation bodies and only reads signatures, so
                # srcs can double as the interface consumers pass via -i -- no separate
                # hand-written interface file needed.
                interfaces = own_interfaces,
                headers = own_headers,
            ),
            linking_context = create_st_linking_context(
                objects = depset([out], transitive = [dep_objects]),
                cc_info = cc_info,
            ),
        ),
        exported_cc_info,
        # Not part of DefaultInfo -- headers aren't needed to link this
        # library, only to hand-write C/C++ code against it. Build with
        # --output_groups=headers to materialize them.
        OutputGroupInfo(headers = own_headers),
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
        "_cc_toolchain": attr.label(default = Label("@rules_cc//cc:current_cc_toolchain")),
    },
    toolchains = ["//st:toolchain_type"] + use_cc_toolchain(),
    fragments = ["cpp"],
    doc = "Compiles ST sources into a relocatable object, for linking into an st_binary/st_test or another st_library.",
)
