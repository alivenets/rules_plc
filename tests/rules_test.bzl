"""bazel_skylib analysis tests for the st_library/st_binary/st_test rule mechanics.

These check the rules' providers and registered actions directly, as opposed
to the compile-and-run integration tests alongside them in this package.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_plc//st:providers.bzl", "StInfo")

def _st_library_provides_st_info_test(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    asserts.true(env, StInfo in target, "st_library target must provide StInfo")
    info = target[StInfo]

    sources = info.compilation_context.sources.to_list()
    asserts.true(
        env,
        any([f.basename == "point_lib.st" for f in sources]),
        "compilation_context.sources should include the library's own .st srcs",
    )
    asserts.true(
        env,
        any([f.basename == "point_types.dut" for f in sources]),
        "compilation_context.sources should include the library's own .dut srcs",
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

def _st_library_facade_test(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    asserts.true(env, StInfo in target, "façade st_library must still provide StInfo")
    info = target[StInfo]

    # A srcs-empty façade must register no StCompile action of its own.
    compile_actions = [a for a in analysistest.target_actions(env) if a.mnemonic == "StCompile"]
    asserts.equals(env, 0, len(compile_actions), "façade st_library must register no StCompile action")

    # StInfo re-exports every dep's sources transitively.
    sources = [f.basename for f in info.compilation_context.sources.to_list()]
    asserts.true(env, "leaf.st" in sources, "façade should re-export leaf.st transitively")
    asserts.true(env, "middle.st" in sources, "façade should re-export middle.st transitively")

    # And every dep's linkable objects.
    objects = info.linking_context.objects.to_list()
    asserts.equals(env, 2, len(objects), "façade should re-export exactly its two deps' objects (leaf, middle)")

    return analysistest.end(env)

st_library_facade_test = analysistest.make(_st_library_facade_test)

def _st_library_interface_deps_facade_test(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    asserts.true(env, StInfo in target, "interface_deps-only façade must still provide StInfo")
    info = target[StInfo]

    # interface_deps demote their sources into OUR interface_sources
    # bucket -- an interface_deps-only façade with no own srcs and no
    # regular deps has an EMPTY `sources` (nothing shippable to a remote
    # plc from this target) and a non-empty `interface_sources` (vendor
    # interface for local compile-time use only).
    sources = [f.basename for f in info.compilation_context.sources.to_list()]
    asserts.equals(env, [], sources, "interface_deps-only façade must expose no owned sources")

    interface_sources = [f.basename for f in info.compilation_context.interface_sources.to_list()]
    asserts.true(env, "leaf.st" in interface_sources, "interface_deps' srcs must land in interface_sources")

    # interface_deps' objects do NOT flow through -- that's the whole
    # point of interface_deps vs deps.
    objects = info.linking_context.objects.to_list()
    asserts.equals(
        env,
        0,
        len(objects),
        "interface_deps-only façade must expose no linkable objects",
    )

    return analysistest.end(env)

st_library_interface_deps_facade_test = analysistest.make(_st_library_interface_deps_facade_test)

def _st_library_mixes_deps_and_interface_deps_test(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    info = target[StInfo]

    # Own srcs stay in `sources`; interface_deps' srcs go to interface_sources.
    sources = [f.basename for f in info.compilation_context.sources.to_list()]
    asserts.true(env, "middle.st" in sources, "own srcs must appear in sources")
    asserts.true(env, "leaf.st" not in sources, "interface_deps' srcs must NOT appear in sources")

    interface_sources = [f.basename for f in info.compilation_context.interface_sources.to_list()]
    asserts.true(env, "leaf.st" in interface_sources, "interface_deps' srcs must appear in interface_sources")

    # Only this library's own object is linkable -- interface_deps'
    # object is intentionally omitted.
    objects = info.linking_context.objects.to_list()
    asserts.equals(
        env,
        1,
        len(objects),
        "linking_context must carry only own object, not interface_deps'",
    )

    return analysistest.end(env)

st_library_mixes_deps_and_interface_deps_test = analysistest.make(_st_library_mixes_deps_and_interface_deps_test)

def _st_library_propagates_interface_sources_through_dep_test(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    info = target[StInfo]

    # A regular dep's interface_sources bucket propagates transitively
    # into ours -- so a downstream packaging rule enumerating our
    # `sources` still filters out the whole vendor-interface chain,
    # however far it lives from us.
    sources = [f.basename for f in info.compilation_context.sources.to_list()]
    asserts.true(env, "top.st" in sources, "own srcs must appear in sources")
    asserts.true(env, "middle.st" in sources, "regular dep's owned srcs must appear in sources")
    asserts.true(env, "leaf.st" not in sources, "transitively-interfaced srcs must NOT reach the owned bucket")

    interface_sources = [f.basename for f in info.compilation_context.interface_sources.to_list()]
    asserts.true(
        env,
        "leaf.st" in interface_sources,
        "a regular dep's interface_sources bucket must propagate into ours",
    )

    return analysistest.end(env)

st_library_propagates_interface_sources_through_dep_test = analysistest.make(_st_library_propagates_interface_sources_through_dep_test)

def _st_binary_omits_interface_deps_objects_from_link_test(ctx):
    env = analysistest.begin(ctx)

    link_actions = [a for a in analysistest.target_actions(env) if a.mnemonic == "StLink"]
    asserts.equals(env, 1, len(link_actions), "st_binary should register exactly one StLink action")
    argv = link_actions[0].argv

    # interface_deps' compiled object must NOT reach the link. Match the
    # basename to stay resilient against bazel-out path shuffling.
    asserts.true(
        env,
        not any([a.endswith("/leaf_lib.o") for a in argv]),
        "interface_deps' object must not appear in the StLink action's argv",
    )

    return analysistest.end(env)

st_binary_omits_interface_deps_objects_from_link_test = analysistest.make(_st_binary_omits_interface_deps_objects_from_link_test)

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
        target_under_test = "//:point_lib_lib",
    )
    st_library_merges_transitive_deps_test(
        name = "st_library_merges_transitive_deps_test",
        target_under_test = "//:top_lib",
    )
    st_library_facade_test(
        name = "st_library_facade_test",
        target_under_test = "//:leaf_middle_facade_lib",
    )
    st_library_interface_deps_facade_test(
        name = "st_library_interface_deps_facade_test",
        target_under_test = "//:leaf_interface_facade_lib",
    )
    st_library_mixes_deps_and_interface_deps_test(
        name = "st_library_mixes_deps_and_interface_deps_test",
        target_under_test = "//:middle_with_interface_leaf_lib",
    )
    st_library_propagates_interface_sources_through_dep_test(
        name = "st_library_propagates_interface_sources_through_dep_test",
        target_under_test = "//:top_over_interface_leaf_lib",
    )
    st_binary_links_with_fuse_ld_lld_test(
        name = "st_binary_links_with_fuse_ld_lld_test",
        target_under_test = "//:trivial_binary_bin",
    )
    st_binary_without_program_skips_wrapper_test(
        name = "st_binary_without_program_skips_wrapper_test",
        target_under_test = "//:no_program_binary_bin",
    )
    st_binary_omits_interface_deps_objects_from_link_test(
        name = "st_binary_omits_interface_deps_objects_from_link_test",
        target_under_test = "//:interface_dep_binary_bin",
    )

    native.test_suite(
        name = name,
        tests = [
            ":st_library_provides_st_info_test",
            ":st_library_merges_transitive_deps_test",
            ":st_library_facade_test",
            ":st_library_interface_deps_facade_test",
            ":st_library_mixes_deps_and_interface_deps_test",
            ":st_library_propagates_interface_sources_through_dep_test",
            ":st_binary_links_with_fuse_ld_lld_test",
            ":st_binary_without_program_skips_wrapper_test",
            ":st_binary_omits_interface_deps_objects_from_link_test",
        ],
    )
