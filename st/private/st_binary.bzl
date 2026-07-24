"""Implementation of the st_binary and st_test rules."""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("//st:providers.bzl", "StInfo", "merge_st_infos")
load("//st:private/headers.bzl", "GENERATE_HEADERS_ATTR", "generate_st_headers")

_MAIN_WRAPPER_TEMPLATE = """FUNCTION main : DINT
VAR
    program_instance : {program_name};
END_VAR
    program_instance();
    main := 0;
END_FUNCTION
"""

def _library_link_name(lib_file):
    """Strips the lib prefix/extension plc's -l/-L (forwarded to the cc linker) expect."""
    name = lib_file.basename
    if name.startswith("lib"):
        name = name[len("lib"):]
    for ext in (".a", ".so", ".dylib", ".lib"):
        if name.endswith(ext):
            return name[:-len(ext)]
    return name

def _cc_libraries_to_link(cc_info):
    """Flattens a CcInfo's linking_context into (library files, extra inputs, extra link args)."""
    if cc_info == None:
        return [], [], []
    files = []
    extra_inputs = []
    link_args = []
    for linker_input in cc_info.linking_context.linker_inputs.to_list():
        link_args.extend(linker_input.user_link_flags)
        extra_inputs.extend(linker_input.additional_inputs)
        for library in linker_input.libraries:
            lib_file = library.pic_static_library or library.static_library or library.dynamic_library or library.interface_library
            if lib_file:
                files.append(lib_file)

                # plc's positional args must be ST sources or .o objects -- it tries to
                # read anything else as ST source. Archives/shared libs go through -L/-l,
                # which plc forwards straight through to the underlying cc linker.
                link_args.append("-L" + lib_file.dirname)
                link_args.append("-l" + _library_link_name(lib_file))
    return files, extra_inputs, link_args

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

    # c_deps implement {external} declarations natively; deps may also carry
    # their own transitively-collected c_deps via dep_info.linking_context.cc_info.
    own_cc_infos = [dep[CcInfo] for dep in ctx.attr.c_deps]
    if dep_info.linking_context.cc_info != None:
        own_cc_infos.append(dep_info.linking_context.cc_info)
    cc_info = cc_common.merge_cc_infos(cc_infos = own_cc_infos) if own_cc_infos else None
    cc_lib_files, cc_extra_inputs, cc_link_args = _cc_libraries_to_link(cc_info)

    out = ctx.actions.declare_file(ctx.label.name)

    args = ctx.actions.args()
    args.add_all(own_objects)
    args.add_all(dep_objects)
    args.add("-o", out)
    args.add_all(cc_link_args)
    args.add("--linker", toolchain.linker.path)
    args.add("--fuse-ld", "lld")

    ctx.actions.run(
        executable = toolchain.compiler,
        arguments = [args],
        inputs = depset(
            own_objects + cc_lib_files + cc_extra_inputs + [toolchain.linker],
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
    own_cc_infos = [dep[CcInfo] for dep in ctx.attr.deps] + [dep[CcInfo] for dep in ctx.attr.c_deps]
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

        # As with st_library, also expose plc's generated C headers for
        # srcs/hdrs on the CcInfo compilation context, so a cc_test depending
        # on this st_binary can #include them (as e.g.
        # "{package}/{name}_st/{module}.h", relative to the
        # workspace/bin root -- see st_library.bzl for why system_includes
        # instead of quote_includes/includes).
        pou_headers_dir = generate_st_headers(ctx, toolchain.compiler, own_pous, dep_interfaces)
        own_compilation_context = cc_common.create_compilation_context(
            headers = depset([pou_headers_dir]),
            system_includes = depset([pou_headers_dir.path]),
        )
        own_cc_infos = [CcInfo(compilation_context = own_compilation_context, linking_context = own_linking_context)] + own_cc_infos
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


_COMMON_ATTRS = dict(
    {
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
        "c_deps": attr.label_list(
            providers = [CcInfo],
            doc = "cc_library targets providing the native implementation of this binary's own {external} FUNCTION/FUNCTION_BLOCK declarations.",
        ),
        "_cc_toolchain": attr.label(default = Label("@rules_cc//cc:current_cc_toolchain")),
    },
    **GENERATE_HEADERS_ATTR
)

st_binary = rule(
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
    doc = "Compiles a PROGRAM (plus any st_library deps) into a native executable, auto-generating the FUNCTION main entry point that runs it. If `program` is omitted, srcs/hdrs are linked as-is (one of them must define its own FUNCTION main).",
)

