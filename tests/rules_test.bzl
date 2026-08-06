"""bazel_skylib analysis tests for the st_library/st_binary/st_test rule mechanics.

These check the rules' providers and registered actions directly, as opposed
to the compile-and-run integration tests alongside them in this package.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//st:providers.bzl", "StInfo")

def _st_library_provides_st_info_test(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    asserts.true(env, StInfo in target, "st_library target must provide StInfo")
    info = target[StInfo]

    interfaces = info.compilation_context.interfaces.to_list()
    asserts.true(
        env,
        any([f.basename == "point_lib.st" for f in interfaces]),
        "compilation_context.interfaces should include the library's own srcs",
    )
    asserts.true(
        env,
        any([f.basename == "point_types.dut" for f in interfaces]),
        "compilation_context.interfaces should include the library's own hdrs",
    )

    objects = info.linking_context.objects.to_list()
    asserts.equals(env, 1, len(objects), "a library with no deps should contribute exactly one object")

    compile_actions = [a for a in analysistest.target_actions(env) if a.mnemonic == "StCompile"]
    asserts.equals(env, 1, len(compile_actions), "st_library should register exactly one StCompile action")

    return analysistest.end(env)

st_library_provides_st_info_test = analysistest.make(_st_library_provides_st_info_test)

def _st_library_merges_transitive_deps_test(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    info = target[StInfo]
    objects = info.linking_context.objects.to_list()
    asserts.equals(
        env,
        3,
        len(objects),
        "top's linking_context should carry its own object plus both transitive deps' (leaf, middle)",
    )

    return analysistest.end(env)

st_library_merges_transitive_deps_test = analysistest.make(_st_library_merges_transitive_deps_test)

def _st_binary_links_with_fuse_ld_lld_test(ctx):
    env = analysistest.begin(ctx)

    actions = [a for a in analysistest.target_actions(env) if a.mnemonic == "StLink"]
    asserts.equals(env, 1, len(actions), "st_binary should register exactly one StLink action")
    action = actions[0]

    argv = action.argv
    asserts.true(env, "--fuse-ld" in argv, "st_binary link action must pass --fuse-ld")
    asserts.true(env, "lld" in argv, "st_binary link action must select the lld backend")
    asserts.true(env, "--linker" in argv, "st_binary link action must pass an explicit --linker")

    return analysistest.end(env)

st_binary_links_with_fuse_ld_lld_test = analysistest.make(_st_binary_links_with_fuse_ld_lld_test)

def _st_binary_without_program_skips_wrapper_test(ctx):
    env = analysistest.begin(ctx)

    validate_actions = [a for a in analysistest.target_actions(env) if a.mnemonic == "StValidateProgram"]
    asserts.equals(env, 0, len(validate_actions), "st_binary with no `program` must not validate/generate a PROGRAM wrapper")

    write_actions = [a for a in analysistest.target_actions(env) if a.mnemonic == "FileWrite"]
    asserts.true(
        env,
        not any([a.outputs.to_list()[0].basename.endswith("_main.st") for a in write_actions]),
        "st_binary with no `program` must not generate a FUNCTION main wrapper",
    )

    link_actions = [a for a in analysistest.target_actions(env) if a.mnemonic == "StLink"]
    asserts.equals(env, 1, len(link_actions), "st_binary should still register exactly one StLink action")

    return analysistest.end(env)

st_binary_without_program_skips_wrapper_test = analysistest.make(_st_binary_without_program_skips_wrapper_test)

def rules_test_suite(name):
    """Registers the analysistest targets defined above.

    The public st_library/st_binary macros (st/private/st_library.bzl,
    st/private/st_binary.bzl) each split into a private "_lib"/"_bin"
    sub-target (registers the StCompile/StLink/etc. actions, provides
    StInfo) plus a headers sub-target, merged into the public name -- these
    tests check the compile-only rule's own registered actions/providers
    directly, so they target that private sub-target, not the public name.

    Args:
      name: unused, kept for native.test_suite-style call conventions.
    """
    st_library_provides_st_info_test(
        name = "st_library_provides_st_info_test",
        target_under_test = "//tests:point_lib_lib",
    )
    st_library_merges_transitive_deps_test(
        name = "st_library_merges_transitive_deps_test",
        target_under_test = "//tests:top_lib",
    )
    st_binary_links_with_fuse_ld_lld_test(
        name = "st_binary_links_with_fuse_ld_lld_test",
        target_under_test = "//tests:trivial_binary_bin",
    )
    st_binary_without_program_skips_wrapper_test(
        name = "st_binary_without_program_skips_wrapper_test",
        target_under_test = "//tests:no_program_binary_bin",
    )

    native.test_suite(
        name = name,
        tests = [
            ":st_library_provides_st_info_test",
            ":st_library_merges_transitive_deps_test",
            ":st_binary_links_with_fuse_ld_lld_test",
            ":st_binary_without_program_skips_wrapper_test",
        ],
    )
