"""Generates plc's C headers for ST sources.

st_library_headers_gen is the private, standalone-generation primitive --
takes raw srcs/deps directly rather than an existing st_library/st_binary
target -- reused by the public st_library and st_binary macros
(st/private/st_library.bzl, st/private/st_binary.bzl) to bundle their own
headers automatically.
"""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//st:providers.bzl", "StHeadersInfo", "StInfo", "merge_st_infos")

def generate_st_headers(ctx, compiler, sources, dep_interfaces, auto_include_sources = []):
    """Runs plc --generate-headers over `sources`.

    Returns a directory (one generated .h per compiled module, named after
    that module, plus a dependencies.plc.h stub) usable as a compilation
    context's `includes`. Requires the calling rule to declare
    `_generate_headers_py` and `_dependencies_plc_h` attrs (see
    st_library_headers_gen's below).

    Args:
      ctx: the calling rule's context.
      compiler: the plc compiler executable File.
      sources: ST source Files to generate headers for.
      dep_interfaces: depset of interface Files from deps, passed as -i.
      auto_include_sources: subset of `sources` to have dependencies.plc.h
        #include automatically -- so any of `sources`' headers pulls them in
        transitively (every generated header already #includes
        <dependencies.plc.h> unconditionally as its own first include),
        instead of requiring consumers to work out the right #include order
        themselves. Must be declaration-only (e.g. hdrs/DUTs) -- a module
        that itself references *other* modules in `sources` risks an
        #include-order hazard if auto-included this way (see
        st/private/generate_headers.py).

    Returns:
      The declared headers directory File.
    """
    headers_dir = ctx.actions.declare_directory(ctx.label.name + "_st")

    header_args = ctx.actions.args()
    header_args.add(compiler.path)
    header_args.add_all(sources)
    header_args.add_all(dep_interfaces, before_each = "-i")
    header_args.add("--generate-headers")
    header_args.add("--header-output", headers_dir.path)

    auto_include_names = ",".join([f.basename.rsplit(".", 1)[0] for f in auto_include_sources])

    ctx.actions.run(
        executable = ctx.executable._generate_headers_py,
        arguments = [headers_dir.path, ctx.file._dependencies_plc_h.path, auto_include_names, header_args],
        inputs = depset([compiler, ctx.file._dependencies_plc_h] + sources, transitive = [dep_interfaces]),
        outputs = [headers_dir],
        mnemonic = "StGenerateHeaders",
        progress_message = "Generating C headers for %{label}",
    )
    return headers_dir

def _st_library_headers_gen_impl(ctx):
    dep_info = merge_st_infos([dep[StInfo] for dep in ctx.attr.deps])
    compiler = ctx.toolchains["//st:toolchain_type"].compiler
    all_sources = ctx.files.srcs + ctx.files.hdrs
    headers_dir = generate_st_headers(
        ctx,
        compiler,
        all_sources,
        dep_info.compilation_context.interfaces,
        auto_include_sources = ctx.files.hdrs,
    )

    compilation_context = cc_common.create_compilation_context(
        headers = depset([headers_dir]),
        system_includes = depset([headers_dir.path]),
    )

    return [
        DefaultInfo(files = depset([headers_dir])),
        CcInfo(compilation_context = compilation_context),
        StHeadersInfo(headers_dir = headers_dir, sources = depset(all_sources)),
    ]

st_library_headers_gen = rule(
    implementation = _st_library_headers_gen_impl,
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = [".st", ".dut"],
            doc = "ST source files to generate C headers for.",
        ),
        "hdrs": attr.label_list(
            allow_files = [".st", ".dut"],
            doc = "Declaration-only files (e.g. .dut TYPE definitions) to generate C headers for alongside srcs. dependencies.plc.h automatically #includes their generated headers (see generate_st_headers) -- must not themselves reference other modules in srcs/hdrs, or this risks an #include-order hazard.",
        ),
        "deps": attr.label_list(
            providers = [StInfo],
            doc = "st_library targets `srcs`/`hdrs` call into, for correctly resolving cross-library types while generating headers.",
        ),
        "_generate_headers_py": attr.label(
            default = Label("//st:generate_headers"),
            executable = True,
            cfg = "exec",
        ),
        "_dependencies_plc_h": attr.label(
            default = Label("//st:private/dependencies.plc.h.jinja"),
            allow_single_file = True,
        ),
    },
    toolchains = ["//st:toolchain_type"],
    doc = "Runs plc --generate-headers over srcs/hdrs, producing a directory of .h files (plus CcInfo/StHeadersInfo wrapping it). Internal -- use the public st_library/st_binary macros (st/private/st_library.bzl, st/private/st_binary.bzl), which bundle headers with a library's/binary's compiled object.",
)
