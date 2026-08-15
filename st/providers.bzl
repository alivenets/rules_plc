"""Providers shared by the ST rules.

StInfo is structured like CcInfo: a compilation context (what a target exposes
to dependents at compile time) plus a linking context (what a target
contributes to the final link), with a merge helper mirroring
cc_common.merge_cc_infos.
"""

# buildifier: disable=name-conventions
StCompilationContext = provider(
    doc = "ST source files a target exposes to dependents at compile time.",
    fields = {
        "sources": "depset of ST source Files (.st/.dut): this target's own srcs plus all transitive deps'. Passed to dependents' compiles via plc's `-i` so cross-library POU/TYPE references resolve.",
    },
)

# buildifier: disable=name-conventions
StLinkingContext = provider(
    doc = "Objects a target contributes to the final link.",
    fields = {
        "objects": "depset of .o Files: this target's compiled object plus all transitive deps'.",
    },
)

StInfo = provider(
    doc = "Compiled ST library: a compilation context and a linking context.",
    fields = {
        "compilation_context": "An StCompilationContext.",
        "linking_context": "An StLinkingContext.",
    },
)

StHeadersInfo = provider(
    doc = "Set by st_library_headers_gen (see st/private/st_headers.bzl) -- and forwarded by the public st_library/st_binary macros' combine steps -- for whatever generated plc's C headers for a target's own srcs. Read by _st_library_stub_source (see st/private/library_stubs.bzl) to scope {external} stub generation to exactly that target's own srcs, using the same already-generated headers rather than regenerating them.",
    fields = {
        "headers_dir": "The directory generate_st_headers produced for this target's own srcs (a single File, not a depset).",
        "sources": "depset of this target's own ST source Files (srcs) headers_dir was generated from.",
    },
)

StTransitiveHeadersInfo = provider(
    doc = "Set on every st_library/st_binary: the union of every underlying library's own StHeadersInfo bundle across the transitive closure. Read by _st_library_stub_source (see st/private/library_stubs.bzl) so a façade st_library (srcs empty, deps only) -- which has no StHeadersInfo of its own -- still fans out weak-stub generation over every underlying leaf library.",
    fields = {
        "bundles": "depset of struct(headers_dir=File, sources=depset<File>), one entry per underlying library that generated its own headers.",
    },
)

StLibraryStubSourceInfo = provider(
    doc = "Set by the private rule generating a target's __attribute__((weak)) stub .c source(s) for its own {external} FUNCTION/FUNCTION_BLOCK declarations (see st/private/library_stubs.bzl). A plain rule reading `library`'s StTransitiveHeadersInfo -- not an aspect -- so it only ever needs the plc toolchain, never a C++ one (kept separate from the rule that compiles the stub sources, which needs a C++ toolchain but not plc's).",
    fields = {
        "stub_cs": "List of generated stub .c Files, one per underlying library in `library`'s transitive closure that declared at least one {external} POU. Empty when nothing to stub.",
        "headers_dirs": "List of headers_dir Files, matching stub_cs positionally, for compiling each stub .c against the exact headers it was generated from.",
        "shim_headers": "List of per-source wrapper .h Files placed at `<shim_root>/<pkg>/<mod>.h`. Each just `#include <mod.h>`, so a stub's workspace-relative `#include \"<pkg>/<mod>.h\"` resolves via -iquote to the wrapper, which falls through to the bundle_dir on -isystem.",
        "shim_root": "Exec-root-relative path of the wrapper tree, passed as -iquote when compiling each stub .c. Empty when there are no stubs to compile.",
    },
)

StLibraryStubsInfo = provider(
    doc = "Set by st_library_stubs_aspect (see st/private/library_stubs.bzl) on the st_library target it's applied to.",
    fields = {
        "cc_info": "A CcInfo linking in a __attribute__((weak)) zero-value stub for each {external} FUNCTION/FUNCTION_BLOCK declared in the target's own srcs, or None if it declared none.",
    },
)

def create_st_compilation_context(sources = depset()):
    return StCompilationContext(sources = sources)

def create_st_linking_context(objects = depset()):
    return StLinkingContext(objects = objects)

def merge_st_infos(st_infos):
    """Merges the compilation and linking contexts of st_infos, mirroring cc_common.merge_cc_infos."""
    return StInfo(
        compilation_context = create_st_compilation_context(
            sources = depset(transitive = [info.compilation_context.sources for info in st_infos]),
        ),
        linking_context = create_st_linking_context(
            objects = depset(transitive = [info.linking_context.objects for info in st_infos]),
        ),
    )
