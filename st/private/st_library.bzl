"""Implementation of the st_library rule."""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//st:private/st_headers.bzl", "st_library_headers_gen")
load("//st:providers.bzl", "StHeadersInfo", "StInfo", "create_st_compilation_context", "create_st_linking_context", "merge_st_infos")

def _st_library_impl(ctx):
    if not ctx.files.srcs and not ctx.files.hdrs:
        fail("%s: st_library must have at least one of srcs or hdrs" % ctx.label)

    toolchain = ctx.toolchains["//st:toolchain_type"]
    compiler = toolchain.compiler

    dep_info = merge_st_infos([dep[StInfo] for dep in ctx.attr.deps])
    dep_objects = dep_info.linking_context.objects
    dep_interfaces = dep_info.compilation_context.interfaces

    # interface_deps are direct-only interface providers: their interface
    # files must be passed to the compiler via `-i` for this target's
    # compilation, but they are not transitive and must not be re-exported
    # via the resulting `StInfo`/linking context.
    interface_dep_infos = [dep[StInfo] for dep in ctx.attr.interface_deps]
    interface_dep_interfaces = depset(transitive = [info.compilation_context.interfaces for info in interface_dep_infos]) if interface_dep_infos else depset()

    # hdrs are full declarations (e.g. .dut TYPE definitions) with no
    # implementation of their own. They're compiled alongside srcs so their
    # constructors are emitted exactly once, by the owning library; dependents
    # only ever see them via -i, never recompiling them.
    # Export only hdrs as compile-time interfaces; srcs are implementation
    # and must not be re-exported to dependents to avoid duplicate symbols
    # for direct-address variables.
    own_interfaces = depset(ctx.files.hdrs, transitive = [dep_interfaces])

    # Own srcs plus all transitive deps' srcs, exposed separately from
    # own_interfaces above via StInfo.compilation_context.sources. Consumers
    # (this rule's own compile below, and st_binary) need this in addition to
    # hdrs-only interfaces to resolve POU types directly instantiated from a
    # dependency's srcs, not just its hdrs, via plc's `-i`.
    own_sources = depset(ctx.files.srcs, transitive = [dep_info.compilation_context.sources])

    # Own compile needs bodies-as-interfaces too (dep_interfaces alone is
    # hdrs-only), same reasoning as own_sources above; this is not re-exported
    # onward -- only own_interfaces (hdrs-only) is.
    dep_compile_interfaces = depset(transitive = [dep_interfaces, dep_info.compilation_context.sources])

    # hdrs-only libraries (no srcs) have no code to compile -- e.g. a
    # library of {external} FUNCTION declarations or .dut TYPE definitions,
    # to be linked in stubbed via st_library_stub -- so skip the StCompile
    # action entirely and produce no object. StInfo still carries the hdrs
    # as compile-time interfaces (own_interfaces above), and CcInfo below
    # just forwards deps'.
    own_objects = []
    default_files = []
    if ctx.files.srcs:
        out = ctx.actions.declare_file(ctx.label.name + ".o")

        args = ctx.actions.args()
        args.add("-c")
        args.add_all(ctx.files.srcs)

        # Own hdrs (e.g. .dut TYPE definitions) are compiled alongside srcs
        # rather than merely made visible via -i, so plc emits their
        # constructors (STRUCT initializers) into this library's object
        # exactly once. Dependents see those ctors as external references,
        # resolved at link time by depending on this library. Passing hdrs
        # only via -i drops the ctors entirely and breaks the link for any
        # struct-typed field a dependent instantiates.
        args.add_all(ctx.files.hdrs)

        args.add_all(dep_compile_interfaces, before_each = "-i")

        # Add direct-only interface deps as -i inputs (non-transitive)
        if interface_dep_interfaces:
            args.add_all(interface_dep_interfaces, before_each = "-i")
        args.add("-o", out)

        ctx.actions.run(
            executable = compiler,
            arguments = [args],
            inputs = depset(ctx.files.srcs + toolchain.compiler_runtime_files, transitive = [own_interfaces, dep_compile_interfaces, interface_dep_interfaces]),
            outputs = [out],
            mnemonic = "StCompile",
            progress_message = "Compiling ST library %{label}",
        )
        own_objects = [out]
        default_files = [out]

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
    own_cc_infos = []
    if own_objects:
        own_linking_context, _ = cc_common.create_linking_context_from_compilation_outputs(
            actions = ctx.actions,
            name = ctx.label.name,
            feature_configuration = feature_configuration,
            cc_toolchain = cc_toolchain,
            compilation_outputs = cc_common.create_compilation_outputs(
                objects = depset(own_objects),
                pic_objects = depset(own_objects),
            ),
            disallow_dynamic_library = True,
        )
        own_cc_infos.append(CcInfo(linking_context = own_linking_context))

    # Does not include plc's generated C headers -- this compile-only rule is
    # wrapped, along with st_library_headers_gen, by the public st_library
    # macro below, which bundles both into one target.
    exported_cc_info = cc_common.merge_cc_infos(cc_infos = own_cc_infos + [dep[CcInfo] for dep in ctx.attr.deps])

    return [
        DefaultInfo(files = depset(default_files)),
        StInfo(
            compilation_context = create_st_compilation_context(
                interfaces = own_interfaces,
                sources = own_sources,
            ),
            linking_context = create_st_linking_context(
                objects = depset(own_objects, transitive = [dep_objects]),
            ),
        ),
        exported_cc_info,
    ]

_st_library = rule(
    implementation = _st_library_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".st"],
            doc = "ST source files implementing this library. Also serves as the interface exposed to targets depending on this library. Optional -- omit for a headers-only library (hdrs only, no implementation of its own).",
        ),
        "hdrs": attr.label_list(
            allow_files = [".dut", ".st"],
            doc = "Full type/declaration files (e.g. .dut TYPE definitions) with no implementation of their own. Compiled alongside srcs and re-exported to dependents, who see them via -i only (never recompiling them).",
        ),
        "deps": attr.label_list(
            providers = [StInfo],
            doc = "Other st_library targets this library's implementation calls into.",
        ),
        "interface_deps": attr.label_list(
            providers = [StInfo],
            doc = "Targets that provide only interface (.st/.dut) files used at compile time via -i; not transitive and not re-exported.",
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

def st_library(name, srcs = [], hdrs = [], deps = [], interface_deps = [], visibility = None, **kwargs):
    """Compiles ST sources into a relocatable object, for linking into an st_binary/st_test or another st_library.

    Also generates and exports plc's C headers for srcs/hdrs, so a
    cc_test/cc_library depending on this target can #include the
    plc-generated .h directly instead of hand-declaring extern "C"
    signatures.

    A headers-only st_library (hdrs only, no srcs) skips compilation and
    produces no object -- useful for a bundle of {external} FUNCTION
    declarations or .dut TYPE definitions consumers link against
    (typically via st_library_stub).

    Args:
        name: Name of this library.
        srcs: ST source files implementing this library. Also serves as the
            interface exposed to targets depending on this library.
            Optional -- omit for a headers-only library.
        hdrs: Full type/declaration files (e.g. .dut TYPE definitions) with
            no implementation of their own. Compiled alongside srcs and
            re-exported to dependents, who see them via -i only (never
            recompiling them).
        deps: Other st_library targets this library's implementation calls into.
        interface_deps: Optional list of st_library targets that provide only
            interface files (srcs/hdrs) which should be passed to the compiler
            as `-i` inputs for this target's compilation. These are direct-only
            and not transitive: `interface_deps` are not merged into the
            resulting `StInfo` or exported `CcInfo` and thus are not visible to
            downstream dependents.
        visibility: Visibility of this library (the underlying compile-only/
            headers-only targets stay private regardless).
        **kwargs: Forwarded to the underlying compile-only rule.
    """
    if not srcs and not hdrs:
        fail("st_library %s: must have at least one of srcs or hdrs" % name)
    compile_name = name + "_lib"
    _st_library(
        name = compile_name,
        srcs = srcs,
        hdrs = hdrs,
        deps = deps,
        interface_deps = interface_deps,
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
