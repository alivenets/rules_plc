"""Implementation of the st_library rule."""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//st:private/st_headers.bzl", "st_library_headers_gen")
load("//st:providers.bzl", "StHeadersInfo", "StInfo", "StTransitiveHeadersInfo", "create_st_compilation_context", "create_st_linking_context", "merge_st_infos")

def _st_library_impl(ctx):
    if not ctx.files.srcs and not ctx.attr.deps:
        fail("%s: st_library must have at least one src or dep" % ctx.label)

    toolchain = ctx.toolchains["//st:toolchain_type"]
    compiler = toolchain.compiler

    dep_info = merge_st_infos([dep[StInfo] for dep in ctx.attr.deps])
    dep_objects = dep_info.linking_context.objects
    dep_sources = dep_info.compilation_context.sources

    # Own srcs plus all transitive deps' srcs, exposed via
    # StInfo.compilation_context.sources so dependents' compiles (and
    # st_binary's) can pass every ST source in the transitive closure to
    # plc via `-i` and resolve any cross-library POU/TYPE reference.
    own_sources = depset(ctx.files.srcs, transitive = [dep_sources])

    # A façade st_library (srcs empty, deps non-empty) skips StCompile
    # entirely: it produces no object of its own and just re-exports its
    # deps' compilation and linking contexts. Useful for grouping several
    # underlying libraries behind one name without adding any code.
    own_objects = []
    default_files = []
    if ctx.files.srcs:
        out = ctx.actions.declare_file(ctx.label.name + ".o")

        args = ctx.actions.args()
        args.add("-c")
        args.add_all(ctx.files.srcs)
        args.add_all(dep_sources, before_each = "-i")

        args.add("-o", out)

        # `--generate-external-constructors` tells plc to emit a strong
        # ctor (plus the matching vtable ctor / instance) for every
        # {external} FB declared in this library's own `-c` sources.
        # plc's own definition of the flag ("Generate constructor for
        # units marked as {external} but not for any included files")
        # already self-restricts to own srcs, so dep-included `{external}`
        # FBs from `-i` sources do not get a duplicate ctor here -- their
        # ctor is emitted by whichever upstream library declares them.
        args.add("--generate-external-constructors")

        ctx.actions.run(
            executable = compiler,
            arguments = [args],
            inputs = depset(ctx.files.srcs + toolchain.compiler_runtime_files, transitive = [dep_sources]),
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

    # Union of each dep's headers bundles -- this compile rule doesn't
    # generate headers of its own (st_library_headers_gen does, and the
    # fusion rule below adds its bundle on top), so only forward whatever
    # the deps already contributed.
    dep_bundles = [
        dep[StTransitiveHeadersInfo].bundles
        for dep in ctx.attr.deps
        if StTransitiveHeadersInfo in dep
    ]

    return [
        DefaultInfo(files = depset(default_files)),
        StInfo(
            compilation_context = create_st_compilation_context(
                sources = own_sources,
            ),
            linking_context = create_st_linking_context(
                objects = depset(own_objects, transitive = [dep_objects]),
            ),
        ),
        StTransitiveHeadersInfo(bundles = depset(transitive = dep_bundles)),
        exported_cc_info,
    ]

_st_library = rule(
    implementation = _st_library_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".st", ".dut"],
            doc = "ST source files (.st implementations and .dut TYPE declarations) making up this library. Compiled into a single object and re-exported to dependents' compiles via plc's `-i` so they can resolve any POU/TYPE reference into this library.",
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
    providers = [
        compile_target[DefaultInfo],
        compile_target[StInfo],
    ]

    # Base is whatever compile_target aggregated from its deps -- add this
    # library's own headers bundle on top when it has any (non-façade case),
    # so a consumer's StTransitiveHeadersInfo lists every underlying leaf's
    # bundle including this one's.
    dep_bundles = compile_target[StTransitiveHeadersInfo].bundles
    if headers_target != None:
        hi = headers_target[StHeadersInfo]
        own_bundle = struct(headers_dir = hi.headers_dir, sources = hi.sources)
        providers.append(StTransitiveHeadersInfo(
            bundles = depset([own_bundle], transitive = [dep_bundles]),
        ))
        providers.append(hi)
        providers.append(cc_common.merge_cc_infos(cc_infos = [compile_target[CcInfo], headers_target[CcInfo]]))
    else:
        # A façade st_library (srcs empty, deps only) has nothing of its own
        # to generate headers for -- forward compile_target's CcInfo and
        # deps' bundles as-is.
        providers.append(StTransitiveHeadersInfo(bundles = dep_bundles))
        providers.append(compile_target[CcInfo])
    return providers

_st_provider_fusion = rule(
    implementation = _st_provider_fusion_impl,
    attrs = {
        "compile": attr.label(mandatory = True, providers = [StInfo, StTransitiveHeadersInfo]),
        "headers": attr.label(providers = [StHeadersInfo]),
    },
    doc = "Combines a compiled st_library with its generated headers (if any) into one target. Internal -- use the public st_library macro below.",
)

def st_library(name, srcs = [], deps = [], visibility = None, **kwargs):
    """Compiles ST sources into a relocatable object, for linking into an st_binary/st_test or another st_library.

    Also generates and exports plc's C headers for srcs, so a
    cc_test/cc_library depending on this target can #include the
    plc-generated .h directly instead of hand-declaring extern "C"
    signatures.

    A façade st_library (srcs empty, deps only) skips compilation and
    header generation: it just re-exports its deps' StInfo/CcInfo under a
    single name, useful for grouping several underlying libraries behind
    one target.

    Args:
        name: Name of this library.
        srcs: ST source files (.st implementations and .dut TYPE
            declarations) making up this library. Compiled into a single
            object and re-exported to dependents' compiles so they can
            resolve any POU/TYPE reference into this library. Optional
            when `deps` is non-empty (façade library).
        deps: Other st_library targets this library's implementation calls into.
        visibility: Visibility of this library (the underlying compile-only/
            headers-only targets stay private regardless).
        **kwargs: Forwarded to the underlying compile-only rule.
    """
    if not srcs and not deps:
        fail("st_library %s: must have at least one of srcs or deps" % name)
    compile_name = name + "_lib"
    _st_library(
        name = compile_name,
        srcs = srcs,
        deps = deps,
        visibility = ["//visibility:private"],
        **kwargs
    )
    headers_gen_name = None
    if srcs:
        headers_gen_name = name + "_headers"
        st_library_headers_gen(
            name = headers_gen_name,
            srcs = srcs,
            deps = deps,
            visibility = ["//visibility:private"],
        )
    _st_provider_fusion(
        name = name,
        compile = compile_name,
        headers = headers_gen_name,
        visibility = visibility,
    )
