"""Implementation of the st_library rule."""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
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

    # --generate-headers is a separate mode -- passing it alongside -c above
    # would skip compilation entirely rather than compile *and* emit headers.
    # With no -o, plc writes one .h per compiled module (named after that
    # module) into --header-output, instead of combining them into one file.
    #
    # plc's own header template unconditionally #includes <dependencies.plc.h>
    # but never emits that file itself, so this action also drops in a stub
    # for it alongside plc's own output -- it must land in the same directory
    # as the generated .h files since they share one -I include path.
    headers_dir = ctx.actions.declare_directory(ctx.label.name + "_headers")

    header_args = ctx.actions.args()
    header_args.add(compiler.path)
    header_args.add_all(ctx.files.srcs)
    header_args.add_all(ctx.files.hdrs)
    header_args.add_all(dep_interfaces, before_each = "-i")
    header_args.add("--generate-headers")
    header_args.add("--header-output", headers_dir.path)

    generate_headers_script = ctx.actions.declare_file(ctx.label.name + "_generate_headers.sh")
    ctx.actions.write(
        output = generate_headers_script,
        content = """#!/usr/bin/env bash
set -eu
"$@"
printf '// Stub for plc-generated headers, which unconditionally #include this;\\n// left empty as st_library has no extra dependency declarations to add.\\n' \\
    > "{headers_dir}/dependencies.plc.h"
""".format(headers_dir = headers_dir.path),
        is_executable = True,
    )

    ctx.actions.run(
        executable = generate_headers_script,
        arguments = [header_args],
        inputs = depset([compiler], transitive = [own_interfaces]),
        outputs = [headers_dir],
        mnemonic = "StGenerateHeaders",
        progress_message = "Generating C headers for ST library %{label}",
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
    exported_cc_info = cc_common.merge_cc_infos(cc_infos = [CcInfo(linking_context = own_linking_context)] +
                                                            [dep[CcInfo] for dep in ctx.attr.deps] +
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
