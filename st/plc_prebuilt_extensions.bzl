"""Bzlmod module extension that fetches a known prebuilt plc release."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

_PLC_RELEASE_BUILD_FILE = """package(default_visibility = [\"//visibility:public\"])
load("@rules_plc//st:defs.bzl", "st_toolchain")

filegroup(name = \"runtime_libs\", srcs = glob([\"*.so\"]))

st_toolchain(
    name = \"plc_compiler\",
    compiler = \":plc\",
    compiler_runtime_files = [\":runtime_libs\"],
    linker = "{linker}",
)

exports_files([\"plc\"])

toolchain(
    name = "plc_toolchain",
    toolchain = \":plc_compiler\",
    toolchain_type = \"@rules_plc//st:toolchain_type\",
)
"""

_PLC_RELEASE_URL = "https://github.com/alivenets/rules_plc/releases/download/0.2.2/plc-linux-x86_64.tar.gz"
_PLC_RELEASE_SHA256 = "235e3e616d3a5c52a6fbd88a6af3d982bffeb79c54a0d6de1b5e8d2ab664c7d3"
_PLC_RELEASE_STRIP_PREFIX = "plc-linux-x86_64"

def _sanitize_label_injections(label_injections):
    """Reduce `{Label(canonical): apparent_label}` to `{canonical_repo: apparent_repo}`.

    Keys are Labels (possibly containing a package/target) and values are
    apparent repo labels. We collapse both sides to the repo-prefix only,
    e.g. a canonical marker with two leading '@' characters becomes the
    canonical repo prefix and `@apparent//pkg:tg` becomes `@apparent`.
    Conflicting mappings for the same canonical repo fail.
    """
    updated = {}
    for canonical, apparent in (label_injections or {}).items():
        canon_repo, _, _ = str(canonical).partition("//")
        apparent_repo, _, _ = apparent.partition("//")
        if not canon_repo or not apparent_repo:
            continue
        existing = updated.get(canon_repo)
        if existing != None and existing != apparent_repo:
            fail("Conflicting label_injections for canonical repo {}: {} vs {}".format(
                canon_repo,
                existing,
                apparent_repo,
            ))
        updated[canon_repo] = apparent_repo

    return updated

def sanitize_label_injections(label_injections):
    """Public wrapper for tests and external users."""
    return _sanitize_label_injections(label_injections)

def _plc_prebuilt_extension_impl(module_ctx):
    for module in module_ctx.modules:
        if not module.is_root:
            fail("Only the root module can use the 'plc' extension")

        for release_attr in module.tags.release:
            linker_label = release_attr.linker

            # Apply any label_injections supplied on the tag: replace apparent
            # repo prefixes in `linker` with their canonical repo prefixes so
            # the generated BUILD content contains canonical markers (which may
            # already include the leading two-@ form). The sanitize function
            # collapses keys/values to repo prefixes only.
            sanitized = _sanitize_label_injections(getattr(release_attr, "label_injections", None))
            if sanitized:
                for canon_repo, apparent_repo in sanitized.items():
                    if linker_label.startswith(apparent_repo):
                        linker_label = canon_repo + linker_label[len(apparent_repo):]
                        break

            # If no mapping produced a canonical repo marker, fall back to the
            # simple doubling of a leading '@' so single-labels like
            # "@llvm_toolchain_llvm//:bin/clang" become a canonical marker
            # with two leading '@' characters.
            double_at = "@" + "@"
            if linker_label.startswith("@") and not linker_label.startswith(double_at):
                linker_label = "@" + linker_label

            http_archive(
                name = release_attr.name,
                url = _PLC_RELEASE_URL,
                sha256 = _PLC_RELEASE_SHA256,
                strip_prefix = _PLC_RELEASE_STRIP_PREFIX,
                build_file_content = _PLC_RELEASE_BUILD_FILE.format(
                    linker = linker_label,
                ),
            )

    return module_ctx.extension_metadata(reproducible = True)

plc = module_extension(
    implementation = _plc_prebuilt_extension_impl,
    tag_classes = {
        "release": tag_class(
            attrs = {
                "name": attr.string(
                    doc = "Repository name for the generated prebuilt plc release.",
                    mandatory = True,
                ),
                "linker": attr.string(
                    doc = "Label for the C++ linker used by the generated st_toolchain.",
                    mandatory = True,
                ),
                "label_injections": attr.label_keyed_string_dict(
                    doc = "A mapping of canonical repo Labels to apparent repo prefixes; applied to `linker` before rendering.",
                    default = {},
                ),
            },
        ),
    },
)
