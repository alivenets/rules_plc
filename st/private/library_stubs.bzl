"""Two private rules (composed by the public st_library_stub macro below)
that generate __attribute__((weak)) zero-value stubs for {external}
FUNCTION/FUNCTION_BLOCK declarations.

A weak symbol is silently overridden by a strong (ordinary) definition of
the same name elsewhere in the final link -- such as a real native
implementation of an {external} declaration, linked in via any ordinary
cc_library dep. Deliberately not wired into st_library/st_binary
automatically: st_library_stub exposes it as its own target, so a
cc_test/st_binary/st_test opts in by adding it to deps, same as it would
any other native library.

Plain rules, not aspects: both only ever need to read `library`'s already-
computed StHeadersInfo (a normal provider, not something needing on-the-fly
aspect computation), so no aspect machinery is needed. This also sidesteps
an exec-platform issue observed when the plc-toolchain-needing step and the
C++-toolchain-needing step were combined into one aspect application (Bazel
selected an exec platform with a broken cc_library solib symlink for plc's
own runtime dependency, libllvm_wrapper.so) -- the same combination
st_library_headers_gen (plc toolchain, no C++) and _st_library/
_st_provider_fusion (C++ toolchain, no plc) already avoid by staying
separate rules.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//st:providers.bzl", "StLibraryStubSourceInfo", "StLibraryStubsInfo", "StTransitiveHeadersInfo")

def _st_library_stub_source_impl(ctx):
    # An st_binary/st_library with nothing of its own to stub (no srcs at
    # all, no deps that generated any headers) carries no
    # StTransitiveHeadersInfo or an empty bundles depset -- either way
    # there's nothing to stub.
    if StTransitiveHeadersInfo not in ctx.attr.library:
        return [StLibraryStubSourceInfo(stub_cs = [], headers_dirs = [], shim_headers = [], shim_root = "")]

    bundles = ctx.attr.library[StTransitiveHeadersInfo].bundles.to_list()
    if not bundles:
        return [StLibraryStubSourceInfo(stub_cs = [], headers_dirs = [], shim_headers = [], shim_root = "")]

    compiler = ctx.toolchains["//st:toolchain_type"].compiler

    stub_cs = []
    headers_dirs = []
    shim_headers = []

    # Shim wrappers live under a per-target subdir so multiple bundles
    # (each in its own Bazel package) can coexist without file-path
    # collisions -- the resulting tree is used as an -iquote root so a
    # stub's `#include "<pkg>/<mod>.h"` resolves against it.
    shim_root_rel = ctx.label.name + "_include"
    shim_root_path = paths.join(ctx.bin_dir.path, ctx.label.package, shim_root_rel)

    # One stub .c per underlying leaf library, keyed off its own headers_dir
    # so each stub .c is compiled against exactly the headers its
    # {external} POUs' prototypes were generated from -- avoids header-name
    # collisions between leaves (e.g. two libs with a same-named module)
    # and keeps each stub .c minimal.
    for i, bundle in enumerate(bundles):
        sources = bundle.sources.to_list()

        # Every source in a bundle comes from a single st_library, so they
        # share a package (short_path directory). Use it as the include
        # prefix so a stub's `#include "<pkg>/<mod>.h"` matches the
        # workspace-relative directory of the underlying .st source.
        include_prefix = paths.dirname(sources[0].short_path) if sources else ""

        # One thin wrapper per source: sits at
        # <shim_root>/<pkg>/<mod>.h in the -iquote tree, and just
        # `#include <mod.h>` -- angle form so it falls through to the
        # bundle's own headers_dir on -isystem (only one bundle_dir per
        # compile, so no ambiguity).
        for src in sources:
            mod = paths.split_extension(src.basename)[0]
            wrapper_rel = paths.join(shim_root_rel, include_prefix, mod + ".h") if include_prefix else paths.join(shim_root_rel, mod + ".h")
            wrapper = ctx.actions.declare_file(wrapper_rel)
            ctx.actions.write(wrapper, "#include <%s.h>\n" % mod)
            shim_headers.append(wrapper)

        stub_c = ctx.actions.declare_file("%s_%d.c" % (ctx.label.name, i))
        ctx.actions.run(
            executable = ctx.executable._generate_weak_stubs_py,
            arguments = [stub_c.path, bundle.headers_dir.path, ctx.file._library_stubs_template.path, compiler.path, include_prefix] +
                        [f.path for f in sources],
            inputs = depset(sources + [bundle.headers_dir, compiler, ctx.file._library_stubs_template]),
            outputs = [stub_c],
            mnemonic = "StGenerateWeakStubs",
            progress_message = "Generating library {external} stubs for %%{label} (bundle %d)" % i,
        )
        stub_cs.append(stub_c)
        headers_dirs.append(bundle.headers_dir)

    return [StLibraryStubSourceInfo(
        stub_cs = stub_cs,
        headers_dirs = headers_dirs,
        shim_headers = shim_headers,
        shim_root = shim_root_path,
    )]

_st_library_stub_source = rule(
    implementation = _st_library_stub_source_impl,
    attrs = {
        "library": attr.label(
            mandatory = True,
            # An st_binary with no srcs of its own doesn't provide any
            # StHeadersInfo (nothing of its own to generate headers for --
            # see st_binary.bzl), but every st_library/st_binary always
            # provides CcInfo, so that's the common check that works for
            # both -- StTransitiveHeadersInfo is checked (softly) in the
            # impl so a plain cc_library `library` still analysis-clean.
            providers = [CcInfo],
        ),
        "_generate_weak_stubs_py": attr.label(
            default = Label("//st:generate_weak_stubs"),
            executable = True,
            cfg = "exec",
        ),
        "_library_stubs_template": attr.label(
            default = Label("//st:private/library_stubs.c.jinja"),
            allow_single_file = True,
        ),
    },
    toolchains = ["//st:toolchain_type"],
    doc = "Generates the __attribute__((weak)) stub .c sources for `library`'s own {external} FUNCTION/FUNCTION_BLOCK declarations across its whole transitive closure (one .c per underlying leaf library that generated headers). Internal -- use the public st_library_stub macro below.",
)

def _st_library_stubs_compile_impl(ctx):
    info = ctx.attr.stub_source[StLibraryStubSourceInfo]
    if not info.stub_cs:
        return [StLibraryStubsInfo(cc_info = None)]

    cc_toolchain = find_cc_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    # One compile per (stub .c, headers_dir) pair, merged into a single
    # linking_context below. Only the stub's own bundle_dir is on the
    # `-isystem` path so `#include <dependencies.plc.h>` from its own
    # module .h unambiguously picks that bundle's own dep.plc.h -- the
    # OTHER bundle_dirs are passed as `headers` (inputs only, no include
    # flag) so the dep-relative `#include "../<sibling>_headers_st/<mod>.h"`
    # (emitted by generate_headers into dep.plc.h) still resolves against
    # the sandboxed file tree.
    #
    # The shim root goes on -iquote so a stub's workspace-relative
    # `#include "<pkg>/<mod>.h"` resolves to the per-source thin wrapper,
    # which in turn `#include <mod.h>` falls through to that stub's own
    # bundle_dir on -isystem.
    all_dep_headers_dir_files = depset(info.headers_dirs)
    shim_header_files = depset(info.shim_headers)
    all_compilation_outputs = []
    for stub_c, bundle_dir in zip(info.stub_cs, info.headers_dirs):
        headers_compilation_context = cc_common.create_compilation_context(
            headers = depset(transitive = [all_dep_headers_dir_files, shim_header_files]),
            system_includes = depset([bundle_dir.path]),
            quote_includes = depset([info.shim_root] if info.shim_root else []),
        )
        _, compilation_outputs = cc_common.compile(
            actions = ctx.actions,
            feature_configuration = feature_configuration,
            cc_toolchain = cc_toolchain,
            name = ctx.label.name + "_" + stub_c.basename.removesuffix(".c"),
            srcs = [stub_c],
            compilation_contexts = [headers_compilation_context],
        )
        all_compilation_outputs.append(compilation_outputs)

    merged_outputs = cc_common.merge_compilation_outputs(compilation_outputs = all_compilation_outputs)
    linking_context, _ = cc_common.create_linking_context_from_compilation_outputs(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        compilation_outputs = merged_outputs,
        name = ctx.label.name,
    )

    return [
        StLibraryStubsInfo(cc_info = CcInfo(linking_context = linking_context)),
        OutputGroupInfo(library_stubs = depset(info.stub_cs)),
    ]

_st_library_stubs_compile = rule(
    implementation = _st_library_stubs_compile_impl,
    attrs = {
        "stub_source": attr.label(mandatory = True, providers = [StLibraryStubSourceInfo]),
        "_cc_toolchain": attr.label(default = Label("@rules_cc//cc:current_cc_toolchain")),
    },
    toolchains = use_cc_toolchain(),
    fragments = ["cpp"],
    doc = "Compiles a generated stub .c source into a CcInfo. Internal -- use the public st_library_stub macro below.",
)

def _st_library_stub_impl(ctx):
    info = ctx.attr.stub_compile[StLibraryStubsInfo]
    return [info.cc_info if info.cc_info != None else CcInfo()]

_st_library_stub = rule(
    implementation = _st_library_stub_impl,
    attrs = {
        "stub_compile": attr.label(mandatory = True, providers = [StLibraryStubsInfo]),
    },
    doc = "Exposes _st_library_stubs_compile's CcInfo as an ordinary target. Internal -- use the public st_library_stub macro below.",
)

def st_library_stub(name, library, visibility = None, **kwargs):
    """A CcInfo target: __attribute__((weak)) zero-value stubs for every {external} FUNCTION/FUNCTION_BLOCK declared in `library`'s own srcs.

    Add to a cc_test/st_binary/st_test's deps so it still links (falling
    back to the stub) when the real native implementation isn't linked in.

    Args:
        name: Name of this target.
        library: The st_library/st_binary to generate {external} library
            stubs for.
        visibility: Visibility of this target (the underlying source-
            generation/compile targets stay private).
        **kwargs: Forwarded to the underlying compile rule.
    """
    source_name = name + "_source"
    _st_library_stub_source(
        name = source_name,
        library = library,
        visibility = ["//visibility:private"],
    )
    compile_name = name + "_compile"
    _st_library_stubs_compile(
        name = compile_name,
        stub_source = source_name,
        visibility = ["//visibility:private"],
        **kwargs
    )
    _st_library_stub(
        name = name,
        stub_compile = compile_name,
        visibility = visibility,
    )
