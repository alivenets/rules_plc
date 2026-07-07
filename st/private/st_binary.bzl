"""Implementation of the st_binary and st_test rules."""

load("//st:providers.bzl", "StInfo", "merge_st_infos")

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

def _link(ctx, toolchain, extra_srcs):
    dep_info = merge_st_infos([dep[StInfo] for dep in ctx.attr.deps])
    dep_objects = dep_info.linking_context.objects
    dep_interfaces = dep_info.compilation_context.interfaces

    # c_deps implement {external} declarations natively; deps may also carry
    # their own transitively-collected c_deps via dep_info.linking_context.cc_info.
    own_cc_infos = [dep[CcInfo] for dep in ctx.attr.c_deps]
    if dep_info.linking_context.cc_info != None:
        own_cc_infos.append(dep_info.linking_context.cc_info)
    cc_info = cc_common.merge_cc_infos(cc_infos = own_cc_infos) if own_cc_infos else None
    cc_lib_files, cc_extra_inputs, cc_link_args = _cc_libraries_to_link(cc_info)

    out = ctx.actions.declare_file(ctx.label.name)

    args = ctx.actions.args()
    args.add_all(extra_srcs)
    args.add_all(ctx.files.hdrs)
    args.add_all(dep_objects)
    args.add_all(dep_interfaces, before_each = "-i")
    args.add("-o", out)
    args.add_all(cc_link_args)
    args.add("--linker", toolchain.linker.path)
    args.add("--fuse-ld", "lld")

    ctx.actions.run(
        executable = toolchain.compiler,
        arguments = [args],
        inputs = depset(
            extra_srcs + ctx.files.hdrs + cc_lib_files + cc_extra_inputs + [toolchain.linker],
            transitive = [dep_objects, dep_interfaces],
        ),
        outputs = [out],
        mnemonic = "StLink",
        progress_message = "Compiling ST binary %{label}",
    )
    return out

def _st_binary_impl(ctx):
    toolchain = ctx.toolchains["//st:toolchain_type"]

    # Convention: the PROGRAM's name matches its file's basename, so the
    # entry-point wrapper below can be generated without parsing the file.
    program_name = ctx.file.main.basename.removesuffix(".st")

    marker = ctx.actions.declare_file(ctx.label.name + "_program_check.marker")
    ctx.actions.run_shell(
        outputs = [marker],
        inputs = [ctx.file.main],
        command = """
set -eu
if ! grep -Eiq '^[[:space:]]*PROGRAM[[:space:]]+{program_name}([[:space:]]|$)' {main}; then
    echo "{main_short_path}: st_binary's main must declare 'PROGRAM {program_name}' (the program name is derived from the main file's basename) -- st_binary generates the FUNCTION main entry point that instantiates and calls it, so main must be a PROGRAM, not a hand-written FUNCTION main" >&2
    exit 1
fi
touch {marker}
""".format(
            program_name = program_name,
            main = ctx.file.main.path,
            main_short_path = ctx.file.main.short_path,
            marker = marker.path,
        ),
        mnemonic = "StValidateProgram",
        progress_message = "Validating %s declares PROGRAM %s" % (ctx.file.main.short_path, program_name),
    )

    wrapper = ctx.actions.declare_file(ctx.label.name + "_main.st")
    ctx.actions.write(
        output = wrapper,
        content = _MAIN_WRAPPER_TEMPLATE.format(program_name = program_name),
    )

    out = _link(ctx, toolchain, extra_srcs = [wrapper, ctx.file.main])

    return [
        DefaultInfo(
            executable = out,
            files = depset([out]),
            runfiles = ctx.runfiles(files = [out]),
        ),
        OutputGroupInfo(_validation = depset([marker])),
    ]

def _st_test_impl(ctx):
    toolchain = ctx.toolchains["//st:toolchain_type"]
    out = _link(ctx, toolchain, extra_srcs = [ctx.file.main])

    return [DefaultInfo(
        executable = out,
        files = depset([out]),
        runfiles = ctx.runfiles(files = [out]),
    )]

_COMMON_ATTRS = {
    "hdrs": attr.label_list(
        allow_files = [".dut", ".st"],
        doc = "Full type/declaration files (e.g. .dut TYPE definitions) local to this binary, with no implementation of their own. Compiled alongside main.",
    ),
    "deps": attr.label_list(
        providers = [StInfo],
        doc = "st_library targets this binary's main file calls into.",
    ),
    "c_deps": attr.label_list(
        providers = [CcInfo],
        doc = "cc_library targets providing the native implementation of this binary's own {external} FUNCTION/FUNCTION_BLOCK declarations.",
    ),
}

st_binary = rule(
    implementation = _st_binary_impl,
    executable = True,
    attrs = dict(
        _COMMON_ATTRS,
        main = attr.label(
            mandatory = True,
            allow_single_file = [".st"],
            doc = "The .st file declaring the PROGRAM that is this binary's cyclic entry point; the PROGRAM's name must match the file's basename. st_binary generates and links in the FUNCTION main wrapper that instantiates and calls it once -- do not write your own FUNCTION main.",
        ),
    ),
    toolchains = ["//st:toolchain_type"],
    doc = "Compiles a PROGRAM (plus any st_library deps) into a native executable, auto-generating the FUNCTION main entry point that runs it.",
)

st_test = rule(
    implementation = _st_test_impl,
    executable = True,
    test = True,
    attrs = dict(
        _COMMON_ATTRS,
        main = attr.label(
            mandatory = True,
            allow_single_file = [".st"],
            doc = "The .st file containing the FUNCTION main entry point.",
        ),
    ),
    toolchains = ["//st:toolchain_type"],
    doc = "Compiles and links an ST main file (plus any st_library deps) into a test executable: the FUNCTION main return value becomes the process exit code (0 = pass).",
)
