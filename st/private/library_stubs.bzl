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

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//st:providers.bzl", "StHeadersInfo", "StLibraryStubSourceInfo", "StLibraryStubsInfo")

def _st_library_stub_source_impl(ctx):
    # An st_binary with neither srcs nor hdrs of its own (just a program)
    # carries no StHeadersInfo -- there's nothing of its own to stub.
    if StHeadersInfo not in ctx.attr.library:
        return [StLibraryStubSourceInfo(stub_c = None, headers_dir = None)]

    headers_info = ctx.attr.library[StHeadersInfo]
    headers_dir = headers_info.headers_dir
    sources = headers_info.sources.to_list()
    compiler = ctx.toolchains["//st:toolchain_type"].compiler

    stub_c = ctx.actions.declare_file(ctx.label.name + ".c")
    ctx.actions.run(
        executable = ctx.executable._generate_weak_stubs_py,
        arguments = [stub_c.path, headers_dir.path, ctx.file._library_stubs_template.path, compiler.path] +
                    [f.path for f in sources],
        inputs = depset(sources + [headers_dir, compiler, ctx.file._library_stubs_template]),
        outputs = [stub_c],
        mnemonic = "StGenerateWeakStubs",
        progress_message = "Generating library {external} stubs for %{label}",
    )

    return [StLibraryStubSourceInfo(stub_c = stub_c, headers_dir = headers_dir)]

_st_library_stub_source = rule(
    implementation = _st_library_stub_source_impl,
    attrs = {
        "library": attr.label(
            mandatory = True,
            # An st_binary with neither srcs nor hdrs of its own doesn't
            # provide StHeadersInfo (nothing of its own to generate headers
            # for -- see st_binary.bzl), but every st_library/st_binary
            # always provides CcInfo, so that's the common check that works
            # for both -- whether it actually has StHeadersInfo is checked
            # (softly) in the impl.
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
    doc = "Generates the __attribute__((weak)) stub .c source for `library`'s own {external} FUNCTION/FUNCTION_BLOCK declarations. Internal -- use the public st_library_stub macro below.",
)

def _st_library_stubs_compile_impl(ctx):
    info = ctx.attr.stub_source[StLibraryStubSourceInfo]
    if info.stub_c == None:
        return [StLibraryStubsInfo(cc_info = None)]

    cc_toolchain = find_cc_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    headers_compilation_context = cc_common.create_compilation_context(
        headers = depset([info.headers_dir]),
        system_includes = depset([info.headers_dir.path]),
    )
    compilation_context, compilation_outputs = cc_common.compile(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        name = ctx.label.name,
        srcs = [info.stub_c],
        compilation_contexts = [headers_compilation_context],
    )
    linking_context, _ = cc_common.create_linking_context_from_compilation_outputs(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        compilation_outputs = compilation_outputs,
        name = ctx.label.name,
    )

    return [
        StLibraryStubsInfo(cc_info = CcInfo(compilation_context = compilation_context, linking_context = linking_context)),
        OutputGroupInfo(library_stubs = depset([info.stub_c])),
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
    """A CcInfo target: __attribute__((weak)) zero-value stubs for every {external} FUNCTION/FUNCTION_BLOCK declared in `library`'s own srcs/hdrs.

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
