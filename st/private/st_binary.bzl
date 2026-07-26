"""Implementation of the st_binary and st_test rules."""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("//st:providers.bzl", "StHeadersInfo", "StInfo", "merge_st_infos")
load("//st:private/st_headers.bzl", "st_library_headers_gen")

_MAIN_WRAPPER_TEMPLATE = """FUNCTION main : DINT
VAR
    program_instance : {program_name};
END_VAR
    program_instance();
    main := 0;
END_FUNCTION
"""

def _compile(ctx, toolchain, out_suffix, sources, dep_interfaces, extra_interfaces = [], progress_verb = "object"):
    """Compiles `sources` (plus interfaces from deps and extra_interfaces) into a single
    relocatable object."""
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
        inputs = depset(sources + extra_interfaces, transitive = [dep_interfaces]),
        outputs = [out],
        mnemonic = "StCompile",
        progress_message = "Compiling ST binary " + progress_verb + " %{label}",
    )
    return out

def _link(ctx, toolchain, own_objects):
    dep_info = merge_st_infos([dep[StInfo] for dep in ctx.attr.deps])
    dep_objects = dep_info.linking_context.objects

    out = ctx.actions.declare_file(ctx.label.name)

    args = ctx.actions.args()
    args.add_all(own_objects)
    args.add_all(dep_objects)
    args.add("-o", out)
    args.add("--linker", toolchain.linker.path)
    args.add("--fuse-ld", "lld")

    ctx.actions.run(
        executable = toolchain.compiler,
        arguments = [args],
        inputs = depset(
            own_objects + [toolchain.linker],
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
    dep_interfaces = dep_info.compilation_context.interfaces

    own_pous = ctx.files.srcs + ctx.files.hdrs
    if ctx.file.program == None and not own_pous:
        fail(("%s must set `program` (an ST PROGRAM to run), `srcs`, or `hdrs` " +
              "(FUNCTION/FUNCTION_BLOCK POUs to export) -- with none of those " +
              "there's nothing to build. For a library with no runnable entry " +
              "point, use st_library instead.") % ctx.label)

    # srcs/hdrs (this binary's own FUNCTION/FUNCTION_BLOCK POUs, as opposed to
    # its PROGRAM entry point) are compiled into their own object, separate
    # from main/wrapper below -- srcs double as their own interface, like
    # st_library does, so program can call into them.
    pou_object = None
    pou_interfaces = []
    if own_pous:
        pou_object = _compile(ctx, toolchain, ".o", own_pous, dep_interfaces, progress_verb = "sources")
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
        # srcs/hdrs above and never exported via CcInfo below -- unlike
        # st_library, this object defines a literal `main` symbol, which
        # would collide with (and silently pre-empt) a cc_test's own main()
        # if it were ever linked into one.
        main_object = _compile(ctx, toolchain, "_main.o", [wrapper, ctx.file.program], dep_interfaces, extra_interfaces = pou_interfaces, progress_verb = "entry point")
        own_objects = [main_object] + ([pou_object] if pou_object else [])
    else:
        # No program: srcs/hdrs (required non-empty above) are linked as-is,
        # with no generated wrapper -- if one of them defines its own
        # FUNCTION main, that's this binary's entry point.
        own_objects = [pou_object]

    out = _link(ctx, toolchain, own_objects)

    # Also export a plain CcInfo, wrapping pou_object (if any) as a linkable
    # library, so non-ST rules (e.g. cc_test's deps) can depend on an
    # st_binary directly to exercise FUNCTION/FUNCTION_BLOCK POUs defined in
    # its own srcs -- the same way st_library does for its own compiled
    # object. main_object is deliberately never part of this -- see above.
    own_cc_infos = [dep[CcInfo] for dep in ctx.attr.deps]
    if pou_object != None:
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
                objects = depset([pou_object]),
                pic_objects = depset([pou_object]),
            ),
            disallow_dynamic_library = True,
        )

        # Does not include plc's generated C headers -- this compile-only rule
        # is wrapped, along with st_library_headers_gen, by the public
        # st_binary macro below, which bundles both into one target (same
        # pattern as st_library).
        own_cc_infos = [CcInfo(linking_context = own_linking_context)] + own_cc_infos
    exported_cc_info = cc_common.merge_cc_infos(cc_infos = own_cc_infos)

    return [
        DefaultInfo(
            executable = out,
            files = depset([out]),
            runfiles = ctx.runfiles(files = [out]),
        ),
        OutputGroupInfo(_validation = depset(validation_outputs)),
        exported_cc_info,
    ]


_COMMON_ATTRS = {
    "srcs": attr.label_list(
        allow_files = [".st"],
        doc = "Additional ST source files implementing FUNCTION/FUNCTION_BLOCK POUs local to this binary, compiled alongside program.",
    ),
    "hdrs": attr.label_list(
        allow_files = [".dut", ".st"],
        doc = "Full type/declaration files (e.g. .dut TYPE definitions) local to this binary, with no implementation of their own. Compiled alongside program.",
    ),
    "deps": attr.label_list(
        providers = [StInfo],
        doc = "st_library targets this binary's program calls into.",
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
            doc = "The .st file declaring the PROGRAM that is this binary's cyclic entry point; the PROGRAM's name must match the file's basename. st_binary generates and links in the FUNCTION main wrapper that instantiates and calls it once -- do not write your own FUNCTION main here. Optional: if omitted, srcs/hdrs are linked as-is with no generated wrapper -- one of them must then define its own FUNCTION main.",
        ),
    ),
    toolchains = ["//st:toolchain_type"] + use_cc_toolchain(),
    fragments = ["cpp"],
    doc = "Compiles a PROGRAM (plus any st_library deps) into a native executable, auto-generating the FUNCTION main entry point that runs it. If `program` is omitted, srcs/hdrs are linked as-is (one of them must define its own FUNCTION main). Internal -- use the public st_binary macro below.",
)

def _st_binary_provider_fusion_impl(ctx):
    binary_target = ctx.attr.binary
    headers_target = ctx.attr.headers
    binary_default_info = binary_target[DefaultInfo]

    # An executable rule's DefaultInfo.executable must be a file this rule's
    # own actions produced, not simply forwarded from binary_target -- so
    # symlink to it instead of reusing binary_default_info.files_to_run
    # directly.
    executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = executable,
        target_file = binary_default_info.files_to_run.executable,
        is_executable = True,
    )

    return [
        DefaultInfo(
            executable = executable,
            files = depset([executable]),
            runfiles = binary_default_info.default_runfiles,
        ),
        binary_target[OutputGroupInfo],
        headers_target[StHeadersInfo],
        cc_common.merge_cc_infos(cc_infos = [binary_target[CcInfo], headers_target[CcInfo]]),
    ]

_st_binary_provider_fusion = rule(
    implementation = _st_binary_provider_fusion_impl,
    executable = True,
    attrs = {
        "binary": attr.label(mandatory = True, executable = True, cfg = "target", providers = [CcInfo]),
        "headers": attr.label(mandatory = True, providers = [CcInfo, StHeadersInfo]),
    },
    doc = "Combines an st_binary with its generated headers into one target, forwarding the binary's own DefaultInfo (so the fused target stays runnable/testable) and OutputGroupInfo (so its _validation actions -- e.g. StValidateProgram -- still run). Internal -- use the public st_binary macro below.",
)

def st_binary(name, srcs = [], hdrs = [], deps = [], program = None, visibility = None, **kwargs):
    """Compiles a PROGRAM (plus any st_library deps) into a native executable, auto-generating the FUNCTION main entry point that runs it.

    If srcs/hdrs are given, also generates and exports plc's C headers for
    them (same as st_library), so a cc_test/cc_library depending on this
    target can #include the plc-generated .h directly instead of hand-
    declaring extern "C" signatures.

    Args:
        name: Name of this binary.
        srcs: Additional ST source files implementing FUNCTION/FUNCTION_BLOCK
            POUs local to this binary, compiled alongside program.
        hdrs: Full type/declaration files (e.g. .dut TYPE definitions) local
            to this binary, with no implementation of their own. Compiled
            alongside program.
        deps: st_library targets this binary's program calls into.
        program: The .st file declaring the PROGRAM that is this binary's
            cyclic entry point; the PROGRAM's name must match the file's
            basename. st_binary generates and links in the FUNCTION main
            wrapper that instantiates and calls it once -- do not write your
            own FUNCTION main here. Optional: if omitted, srcs/hdrs are
            linked as-is with no generated wrapper -- one of them must then
            define its own FUNCTION main.
        visibility: Visibility of this binary (the underlying compile-only/
            headers-only targets stay private regardless).
        **kwargs: Forwarded to the underlying compile-only rule.
    """
    bin_name = name + "_bin"
    _st_binary(
        name = bin_name,
        srcs = srcs,
        hdrs = hdrs,
        deps = deps,
        program = program,
        visibility = ["//visibility:private"],
        **kwargs
    )
    if not srcs and not hdrs:
        # Nothing of this binary's own to generate headers for (its PROGRAM
        # entry point, if any, is never exported -- see _st_binary_impl).
        native.alias(name = name, actual = bin_name, visibility = visibility)
        return

    headers_gen_name = name + "_headers"
    st_library_headers_gen(
        name = headers_gen_name,
        srcs = srcs,
        hdrs = hdrs,
        deps = deps,
        visibility = ["//visibility:private"],
    )
    _st_binary_provider_fusion(
        name = name,
        binary = bin_name,
        headers = headers_gen_name,
        visibility = visibility,
    )

