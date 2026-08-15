"""Implementation of the st_binary and st_test rules."""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//st:private/st_headers.bzl", "st_library_headers_gen")
load(
    "//st:providers.bzl",
    "StHeadersInfo",
    "StInfo",
    "create_st_compilation_context",
    "create_st_linking_context",
    "merge_st_infos",
)

_MAIN_WRAPPER_TEMPLATE = """FUNCTION main : DINT
VAR
    program_instance : {program_name};
END_VAR
    program_instance();
    main := 0;
END_FUNCTION
"""

def _compile(ctx, toolchain, out_suffix, sources, dep_interfaces, extra_interfaces = [], progress_verb = "object"):
    """Compiles `sources` (plus interfaces from deps and extra_interfaces) into a single relocatable object."""
    out = ctx.actions.declare_file(ctx.label.name + out_suffix)

    args = ctx.actions.args()
    args.add("-c")
    args.add_all(sources)
    args.add_all(dep_interfaces, before_each = "-i")
    args.add_all(extra_interfaces, before_each = "-i")
    args.add("-o", out)

    # st_binary's objects (unlike st_library's) are linked straight into a
    # PIE executable below, which requires PIC relocations -- plc's -c
    # defaults to non-PIC, which ld.lld rejects with R_X86_64_32 errors.
    args.add("--fpic")

    ctx.actions.run(
        executable = toolchain.compiler,
        arguments = [args],
        inputs = depset(sources + extra_interfaces + toolchain.compiler_runtime_files, transitive = [dep_interfaces]),
        outputs = [out],
        mnemonic = "StCompile",
        progress_message = "Compiling ST binary " + progress_verb + " %{label}",
    )
    return out

def _collect_cc_link_files(cc_infos):
    """Flattens `cc_infos` into the object Files to pass to plc's link step.

    plc's linker driver only understands raw object files, not .a archives,
    so this pulls each LibraryToLink's constituent objects rather than its
    archive. PIC objects preferred (this binary is linked with --fpic, and
    mixing non-PIC into that triggers R_X86_64_32 relocation errors under
    ld.lld); falls back to non-PIC when a library only has that.

    Also pulls in an archive's objects unconditionally (no --whole-archive/
    --as-needed selection here) -- for weak-stub .a's, this is exactly the
    intent, and for ordinary cc_library deps it matches how ST's own
    st_library objects are already linked.
    """
    files = []
    for cc_info in cc_infos:
        for linker_input in cc_info.linking_context.linker_inputs.to_list():
            for lib in linker_input.libraries:
                if lib.pic_objects:
                    files.extend(lib.pic_objects)
                elif lib.objects:
                    files.extend(lib.objects)
                elif lib.pic_static_library:
                    files.append(lib.pic_static_library)
                elif lib.static_library:
                    files.append(lib.static_library)
                elif lib.dynamic_library:
                    files.append(lib.dynamic_library)
    return files

def _link(ctx, toolchain, own_objects, cc_link_files):
    dep_info = merge_st_infos([dep[StInfo] for dep in ctx.attr.deps])
    dep_objects = dep_info.linking_context.objects

    # interface_deps intentionally contribute nothing to the link -- their
    # StInfo objects are compile-time-only. Their real implementation is
    # provided elsewhere, typically via this binary's cc_deps.

    out = ctx.actions.declare_file(ctx.label.name)

    # A cc_dep may transitively re-export an st_library that already
    # appears in `deps` (e.g. a cc_library wrapping an {external} POU
    # implementation, with the underlying st_library in its own deps).
    # That library's compiled object then reaches this link step twice:
    # once via `dep_objects` (StInfo transitively) and once via
    # `cc_link_files` (CcInfo transitively). plc's linker driver hands
    # every input straight to ld.lld, which rejects the duplicate as a
    # duplicate-symbol error. Dedupe by File identity, preserving the
    # own -> deps -> cc_deps order.
    seen = {}
    link_files = []
    for f in own_objects + dep_objects.to_list() + cc_link_files:
        if f.path in seen:
            continue
        seen[f.path] = True
        link_files.append(f)

    args = ctx.actions.args()
    args.add_all(link_files)
    args.add("-o", out)
    args.add("--linker", toolchain.linker.path)
    args.add("--fuse-ld", "lld")

    ctx.actions.run(
        executable = toolchain.compiler,
        arguments = [args],
        inputs = depset(
            own_objects + cc_link_files + [toolchain.linker] + toolchain.compiler_runtime_files,
            transitive = [dep_objects],
        ),
        outputs = [out],
        mnemonic = "StLink",
        progress_message = "Linking ST binary %{label}",
    )
    return out

def _st_binary_impl(ctx):
    toolchain = ctx.toolchains["//st:toolchain_type"]

    dep_info = merge_st_infos([dep[StInfo] for dep in ctx.attr.deps])

    # Regular deps: their `sources` stay owned (shipped with this binary
    # in a hypothetical remote-compile packaging step); their own
    # `interface_sources` propagate transitively into ours.
    dep_owned_sources = dep_info.compilation_context.sources
    dep_interface_sources = dep_info.compilation_context.interface_sources

    # interface_deps: everything the dep exposes is demoted into OUR
    # interface_sources bucket -- see _st_library_impl for the rationale.
    interface_dep_infos = [dep[StInfo] for dep in ctx.attr.interface_deps]
    interface_dep_sources_bucket = depset(
        transitive = [
                         dep_interface_sources,
                     ] + [info.compilation_context.sources for info in interface_dep_infos] +
                     [info.compilation_context.interface_sources for info in interface_dep_infos],
    )

    # Every ST source in the transitive closure (both dep flavors, from
    # both buckets) is passed to plc via `-i` so this binary's program
    # can resolve any POU/TYPE declared in a dep -- see
    # StCompilationContext.sources / interface_sources in
    # //st:providers.bzl.
    dep_sources = depset(transitive = [dep_owned_sources, interface_dep_sources_bucket])

    own_pous = ctx.files.srcs
    if ctx.file.program == None and not own_pous:
        fail(("%s must set `program` (an ST PROGRAM to run) or `srcs` " +
              "(FUNCTION/FUNCTION_BLOCK POUs to export) -- with neither " +
              "there's nothing to build. For a library with no runnable entry " +
              "point, use st_library instead.") % ctx.label)

    # srcs (this binary's own FUNCTION/FUNCTION_BLOCK POUs, as opposed to
    # its PROGRAM entry point) are compiled into their own object, separate
    # from main/wrapper below -- srcs double as their own interface, like
    # st_library does, so program can call into them.
    pou_object = None
    pou_interfaces = []
    if own_pous:
        pou_object = _compile(ctx, toolchain, ".o", own_pous, dep_sources, progress_verb = "sources")
        pou_interfaces = own_pous

    validation_outputs = []
    if ctx.file.program != None:
        # Convention: the PROGRAM's name matches its file's basename, so the
        # entry-point wrapper below can be generated without parsing the file.
        program_name = ctx.file.program.basename.removesuffix(".st")

        marker = ctx.actions.declare_file(ctx.label.name + "_program_check.marker")
        ctx.actions.run_shell(
            outputs = [marker],
            inputs = [ctx.file.program],
            command = """
set -eu
if ! grep -Eiq '^[[:space:]]*PROGRAM[[:space:]]+{program_name}([[:space:]]|$)' {program}; then
    echo "{program_short_path}: st_binary's program must declare 'PROGRAM {program_name}' (the program name is derived from the program file's basename) -- st_binary generates the FUNCTION main entry point that instantiates and calls it, so program must be a PROGRAM, not a hand-written FUNCTION main" >&2
    exit 1
fi
touch {marker}
""".format(
                program_name = program_name,
                program = ctx.file.program.path,
                program_short_path = ctx.file.program.short_path,
                marker = marker.path,
            ),
            mnemonic = "StValidateProgram",
            progress_message = "Validating %s declares PROGRAM %s" % (ctx.file.program.short_path, program_name),
        )
        validation_outputs.append(marker)

        wrapper = ctx.actions.declare_file(ctx.label.name + "_main.st")
        ctx.actions.write(
            output = wrapper,
            content = _MAIN_WRAPPER_TEMPLATE.format(program_name = program_name),
        )

        # main/wrapper (the PROGRAM entry point) is compiled separately from
        # srcs above and never exported via CcInfo below -- unlike
        # st_library, this object defines a literal `main` symbol, which
        # would collide with (and silently pre-empt) a cc_test's own main()
        # if it were ever linked into one.
        main_object = _compile(ctx, toolchain, "_main.o", [wrapper, ctx.file.program], dep_sources, extra_interfaces = pou_interfaces, progress_verb = "entry point")
        own_objects = [main_object] + ([pou_object] if pou_object else [])
    else:
        # No program: srcs (required non-empty above) are linked as-is,
        # with no generated wrapper -- if one of them defines its own
        # FUNCTION main, that's this binary's entry point.
        own_objects = [pou_object]

    cc_dep_cc_infos = [dep[CcInfo] for dep in ctx.attr.cc_deps]
    cc_link_files = _collect_cc_link_files(cc_dep_cc_infos)

    out = _link(ctx, toolchain, own_objects, cc_link_files)

    # Export a plain CcInfo constructed from StInfo linking contexts of
    # `deps`, so linking a `st_binary` against `st_library` uses the ST
    # objects (not any CcInfo that may re-export unrelated C++ objects).
    # Build a CcInfo for each st dep by wrapping its StInfo.linking_context
    # objects into a cc linking context.
    cc_toolchain = find_cc_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    dep_cc_infos = []
    for dep in ctx.attr.deps:
        st_info = dep[StInfo]
        dep_linking_context, _ = cc_common.create_linking_context_from_compilation_outputs(
            actions = ctx.actions,
            name = dep.label.name,
            feature_configuration = feature_configuration,
            cc_toolchain = cc_toolchain,
            compilation_outputs = cc_common.create_compilation_outputs(
                objects = st_info.linking_context.objects,
                pic_objects = st_info.linking_context.objects,
            ),
            disallow_dynamic_library = True,
        )
        dep_cc_infos.append(CcInfo(linking_context = dep_linking_context))

    if pou_object != None:
        own_linking_context, _ = cc_common.create_linking_context_from_compilation_outputs(
            actions = ctx.actions,
            name = ctx.label.name,
            feature_configuration = feature_configuration,
            cc_toolchain = cc_toolchain,
            compilation_outputs = cc_common.create_compilation_outputs(
                objects = depset([pou_object]),
                pic_objects = depset([pou_object]),
            ),
            disallow_dynamic_library = True,
        )
        own_cc_infos = [CcInfo(linking_context = own_linking_context)] + dep_cc_infos
    else:
        own_cc_infos = dep_cc_infos

    exported_cc_info = cc_common.merge_cc_infos(cc_infos = own_cc_infos + cc_dep_cc_infos)

    # Also expose an StInfo, mirroring st_library, so an st_binary can
    # feed another st_binary/st_library's `deps` -- carrying its own
    # non-program srcs (which double as their interface, same as
    # st_library) and its own compiled POU object plus every dep's,
    # minus the entry-point wrapper (which defines `main` and must not
    # leak into a downstream link).
    #
    # The two source buckets stay separate: `sources` holds this
    # binary's own non-program srcs plus regular deps' owned sources
    # (shippable to a remote plc), and `interface_sources` holds
    # everything demoted via any interface_deps chain (vendor
    # interfaces).
    st_info = StInfo(
        compilation_context = create_st_compilation_context(
            sources = depset(ctx.files.srcs, transitive = [dep_owned_sources]),
            interface_sources = interface_dep_sources_bucket,
        ),
        linking_context = create_st_linking_context(
            objects = depset(
                [pou_object] if pou_object else [],
                transitive = [dep_info.linking_context.objects],
            ),
        ),
    )

    return [
        DefaultInfo(
            executable = out,
            files = depset([out]),
            runfiles = ctx.runfiles(files = [out]),
        ),
        OutputGroupInfo(_validation = depset(validation_outputs)),
        exported_cc_info,
        st_info,
    ]

_COMMON_ATTRS = {
    "srcs": attr.label_list(
        allow_files = [".st", ".dut"],
        doc = "Additional ST source files (.st implementations, .dut TYPE declarations) local to this binary, compiled alongside program.",
    ),
    "deps": attr.label_list(
        providers = [StInfo],
        doc = "st_library targets this binary's program calls into.",
    ),
    "interface_deps": attr.label_list(
        providers = [StInfo],
        doc = "st_library targets this binary's program calls into, at the source/interface level only -- their compiled objects are NOT linked. Use for {external} POU declarations whose real implementation is provided via `cc_deps` instead, to avoid the stubbed-out or duplicate-symbol object from reaching ld.",
    ),
    "cc_deps": attr.label_list(
        providers = [CcInfo],
        doc = "Native (C/C++) libraries linked into this binary -- e.g. an st_library_stub, or an ordinary cc_library implementing {external} POUs declared in a dep's srcs. Their libraries/objects are passed straight to plc's link step; their compilation context is not consumed (ST sources don't #include C headers).",
    ),
    "_cc_toolchain": attr.label(default = Label("@rules_cc//cc:current_cc_toolchain")),
}

_st_binary = rule(
    implementation = _st_binary_impl,
    executable = True,
    attrs = dict(
        _COMMON_ATTRS,
        program = attr.label(
            allow_single_file = [".st"],
            doc = "The .st file declaring the PROGRAM that is this binary's cyclic entry point; the PROGRAM's name must match the file's basename. st_binary generates and links in the FUNCTION main wrapper that instantiates and calls it once -- do not write your own FUNCTION main here. Optional: if omitted, srcs are linked as-is with no generated wrapper -- one of them must then define its own FUNCTION main.",
        ),
    ),
    toolchains = ["//st:toolchain_type"] + use_cc_toolchain(),
    fragments = ["cpp"],
    doc = "Compiles a PROGRAM (plus any st_library deps) into a native executable, auto-generating the FUNCTION main entry point that runs it. If `program` is omitted, srcs are linked as-is (one of them must define its own FUNCTION main). Internal -- use the public st_binary macro below.",
)

def _st_binary_provider_fusion_impl(ctx):
    binary_target = ctx.attr.binary
    headers_target = ctx.attr.headers
    binary_default_info = binary_target[DefaultInfo]

    executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = executable,
        target_file = binary_default_info.files_to_run.executable,
        is_executable = True,
    )

    providers = [
        DefaultInfo(
            executable = executable,
            files = depset([executable]),
            runfiles = binary_default_info.default_runfiles,
        ),
        binary_target[OutputGroupInfo],
        binary_target[StInfo],
    ]
    if headers_target != None:
        providers.append(headers_target[StHeadersInfo])
        providers.append(cc_common.merge_cc_infos(cc_infos = [binary_target[CcInfo], headers_target[CcInfo]]))
    else:
        # No srcs of its own to generate headers for -- see st_binary
        # below.
        providers.append(binary_target[CcInfo])

    return providers

_st_binary_provider_fusion = rule(
    implementation = _st_binary_provider_fusion_impl,
    executable = True,
    attrs = {
        "binary": attr.label(mandatory = True, executable = True, cfg = "target", providers = [CcInfo, StInfo]),
        "headers": attr.label(providers = [CcInfo, StHeadersInfo]),
    },
    doc = "Combines an st_binary with its generated headers (if any) into one target, forwarding the binary's own DefaultInfo (so the fused target stays runnable/testable) and OutputGroupInfo (so its _validation actions -- e.g. StValidateProgram -- still run). Internal -- use the public st_binary macro below.",
)

def st_binary(name, srcs = [], deps = [], interface_deps = [], cc_deps = [], program = None, visibility = None, **kwargs):
    """Compiles a PROGRAM (plus any st_library deps) into a native executable, auto-generating the FUNCTION main entry point that runs it.

    If srcs are given, also generates and exports plc's C headers for them
    (same as st_library), so a cc_test/cc_library depending on this target
    can #include the plc-generated .h directly instead of hand-declaring
    extern "C" signatures.

    Args:
        name: Name of this binary.
        srcs: Additional ST source files (.st implementations, .dut TYPE
            declarations) local to this binary, compiled alongside program.
        deps: st_library targets this binary's program calls into.
        interface_deps: st_library targets this binary's program calls into,
            at the source/interface level only -- their compiled objects
            are NOT linked. Use for {external} POU declarations whose real
            implementation is provided via `cc_deps` instead, to avoid the
            stubbed-out or duplicate-symbol object from reaching ld.
        cc_deps: Native (C/C++) libraries linked into this binary -- e.g. an
            st_library_stub, or an ordinary cc_library implementing
            {external} POUs declared in a dep's srcs.
        program: The .st file declaring the PROGRAM that is this binary's
            cyclic entry point; the PROGRAM's name must match the file's
            basename. st_binary generates and links in the FUNCTION main
            wrapper that instantiates and calls it once -- do not write your
            own FUNCTION main here. Optional: if omitted, srcs are linked
            as-is with no generated wrapper -- one of them must then define
            its own FUNCTION main.
        visibility: Visibility of this binary (the underlying compile-only/
            headers-only targets stay private regardless).
        **kwargs: Forwarded to the underlying compile-only rule.
    """
    bin_name = name + "_bin"
    _st_binary(
        name = bin_name,
        srcs = srcs,
        deps = deps,
        interface_deps = interface_deps,
        cc_deps = cc_deps,
        program = program,
        visibility = ["//visibility:private"],
        **kwargs
    )

    # Always fused, even with no headers to generate.
    headers_gen_name = None
    if srcs:
        headers_gen_name = name + "_headers"
        st_library_headers_gen(
            name = headers_gen_name,
            srcs = srcs,
            # Both dep flavors' sources need to be visible to plc's
            # header-gen step for cross-library type resolution.
            deps = deps + interface_deps,
            visibility = ["//visibility:private"],
        )
    _st_binary_provider_fusion(
        name = name,
        binary = bin_name,
        headers = headers_gen_name,
        visibility = visibility,
    )
