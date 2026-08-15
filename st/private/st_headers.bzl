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

def _relativize(from_dir, to_path):
    """Path components joining `to_path` (file, exec-root-relative) starting from `from_dir` (directory, same-root).

    Both are workspace/exec-root-relative and share at least the "bazel-out
    or workspace" root prefix, so the walk always terminates. Used to
    render `#include "<rel>/<module>.h"` in dependencies.plc.h for a dep
    library's own header, so the C compiler resolves it relative to this
    dep.plc.h's own directory -- no ambiguity with any same-named header
    that plc may have also emitted into this library's own headers_dir
    alongside dep.plc.h (angle-bracket form would let the first
    same-basename hit on the include path win instead).
    """
    from_parts = from_dir.split("/")
    to_parts = to_path.split("/")
    common = 0
    for i in range(min(len(from_parts), len(to_parts))):
        if from_parts[i] != to_parts[i]:
            break
        common = i + 1
    return "/".join([".."] * (len(from_parts) - common) + to_parts[common:])

def generate_st_headers(ctx, compiler, sources, dep_sources, auto_include_sources = [], dep_auto_include_bundles = []):
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
      dep_sources: depset of source Files from deps, passed as -i.
      auto_include_sources: subset of `sources` to have dependencies.plc.h
        #include automatically -- so any of `sources`' headers pulls them in
        transitively (every generated header already #includes
        <dependencies.plc.h> unconditionally as its own first include),
        instead of requiring consumers to work out the right #include order
        themselves. Must be declaration-only (e.g. .dut TYPE definitions) --
        a module that itself references *other* modules in `sources` risks
        an #include-order hazard if auto-included this way (see
        st/private/generate_headers.py). Rendered as `#include "name.h"`
        (same-directory quote form) since they live alongside the file
        dependencies.plc.h.
      dep_auto_include_bundles: list of struct(headers_dir=File,
        sources=list<File>), one per dep whose own headers should be
        transitively re-exported. Each entry's sources are rendered into
        dependencies.plc.h as `#include "<rel>/<module>.h"` where <rel> is
        computed once per dep as the relative path from this library's own
        headers_dir to the dep's headers_dir. Quote form so the C
        compiler resolves each include relative to dep.plc.h's directory
        -- no ambiguity with any same-basename header plc may have also
        emitted into this library's own headers_dir.

    Returns:
      The declared headers directory File.
    """
    headers_dir = ctx.actions.declare_directory(ctx.label.name + "_st")

    header_args = ctx.actions.args()
    header_args.add(compiler.path)
    header_args.add_all(sources)
    header_args.add_all(dep_sources, before_each = "-i")
    header_args.add("--generate-headers")
    header_args.add("--header-output", headers_dir.path)

    auto_include_names = ",".join([f.basename.rsplit(".", 1)[0] for f in auto_include_sources])

    dep_auto_include_paths = []
    for bundle in dep_auto_include_bundles:
        rel = _relativize(headers_dir.path, bundle.headers_dir.path)
        for src in bundle.sources:
            name = src.basename.rsplit(".", 1)[0]
            dep_auto_include_paths.append(rel + "/" + name if rel else name)
    dep_auto_include_names = ",".join(dep_auto_include_paths)

    ctx.actions.run(
        executable = ctx.executable._generate_headers_py,
        arguments = [headers_dir.path, ctx.file._dependencies_plc_h.path, auto_include_names, dep_auto_include_names, header_args],
        inputs = depset([compiler, ctx.file._dependencies_plc_h] + sources, transitive = [dep_sources]),
        outputs = [headers_dir],
        mnemonic = "StGenerateHeaders",
        progress_message = "Generating C headers for %{label}",
    )
    return headers_dir

def _st_library_headers_gen_impl(ctx):
    dep_info = merge_st_infos([dep[StInfo] for dep in ctx.attr.deps])
    compiler = ctx.toolchains["//st:toolchain_type"].compiler
    all_sources = ctx.files.srcs

    # .dut files carry only TYPE declarations (no POU bodies), so they're
    # safe to auto-include from dependencies.plc.h -- any of this library's
    # own generated headers then pulls the .dut declarations in
    # transitively without consumers having to work out the right
    # #include order themselves.
    dut_sources = [f for f in ctx.files.srcs if f.extension == "dut"]

    # Every dep's own source basenames (via StHeadersInfo.sources) are
    # auto-included too, so a C/C++ consumer of this library's headers
    # transitively gets every dep's type/POU declarations via one #include.
    # Each dep contributes a (headers_dir, sources) bundle so
    # generate_st_headers can render each dep header as a relative-path
    # #include from this library's own dependencies.plc.h -- resolving
    # unambiguously to the authoritative dep-generated header rather than
    # any same-basename copy plc may have emitted into this library's own
    # headers_dir. Skips deps that provide no StHeadersInfo (e.g. a
    # façade st_library with no srcs of its own -- its own deps are picked
    # up here via the dep_info walk below).
    dep_auto_include_bundles = []
    for dep in ctx.attr.deps:
        if StHeadersInfo in dep:
            hi = dep[StHeadersInfo]
            dep_auto_include_bundles.append(struct(
                headers_dir = hi.headers_dir,
                sources = hi.sources.to_list(),
            ))

    # Both source buckets go to plc's `-i`: vendor interfaces are needed
    # for cross-library type resolution just as much as owned sources are.
    all_dep_sources = depset(
        transitive = [
            dep_info.compilation_context.sources,
            dep_info.compilation_context.interface_sources,
        ],
    )

    headers_dir = generate_st_headers(
        ctx,
        compiler,
        all_sources,
        all_dep_sources,
        auto_include_sources = dut_sources,
        dep_auto_include_bundles = dep_auto_include_bundles,
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
            allow_files = [".st", ".dut"],
            doc = "ST source files to generate C headers for.",
        ),
        "deps": attr.label_list(
            providers = [StInfo],
            doc = "st_library targets `srcs` call into, for correctly resolving cross-library types while generating headers.",
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
    doc = "Runs plc --generate-headers over srcs, producing a directory of .h files (plus CcInfo/StHeadersInfo wrapping it). Internal -- use the public st_library/st_binary macros (st/private/st_library.bzl, st/private/st_binary.bzl), which bundle headers with a library's/binary's compiled object.",
)
