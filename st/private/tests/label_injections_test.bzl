"""Unit tests for `sanitize_label_injections` and related utilities."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# Load the public wrapper from the plc extension implementation.
load("//st:plc_prebuilt_extensions.bzl", "sanitize_label_injections")

def _basic_test_impl(ctx):
    env = unittest.begin(ctx)

    # Empty input -> empty output
    asserts.equals(env, {}, sanitize_label_injections({}))

    # Simple apparent value with repo prefix
    result = sanitize_label_injections({Label("@bazel_skylib//:defs.bzl"): "@apparent_repo//pkg:target"})
    asserts.equals(env, 1, len(result))
    key = result.keys()[0]
    asserts.true(env, "//" not in key)
    asserts.equals(env, "@apparent_repo", result[key])

    # Multiple distinct canonical repos
    result = sanitize_label_injections({
        Label("@a//:b"): "@apparent1//:x",
        Label("@c//d:e"): "@apparent2//pkg:tg",
    })
    asserts.equals(env, 2, len(result))
    values = sorted(result.values())
    asserts.equals(env, sorted(["@apparent1", "@apparent2"]), values)

    return unittest.end(env)

basic_test = unittest.make(_basic_test_impl)

def label_injections_test_suite(name):
    basic_test(name = "basic_test")

    native.test_suite(
        name = name,
        tests = ["basic_test"],
    )
