"""Providers shared by the ST rules.

StInfo is structured like CcInfo: a compilation context (what a target exposes
to dependents at compile time) plus a linking context (what a target
contributes to the final link), with a merge helper mirroring
cc_common.merge_cc_infos.
"""

# buildifier: disable=name-conventions
StCompilationContext = provider(
    doc = "Interface files a target exposes to dependents at compile time.",
    fields = {
        "interfaces": "depset of declaration-only interface Files (hdrs): this target's plus all transitive deps'. Safe to pass to plc's `-i` at any depth -- hdrs carry no implementation, so re-exporting them never causes duplicate symbols.",
        "sources": "depset of implementation ST source Files (srcs): this target's plus all transitive deps'. Unlike `interfaces`, this also carries dependency bodies, which plc's `-i` needs to resolve POU types directly instantiated from a dep's srcs (not just its hdrs) -- read by this target's own compile plus st_binary's, but never re-exported as `interfaces` to further dependents.",
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
    doc = "Set by st_library_headers_gen (see st/private/st_headers.bzl) -- and forwarded by the public st_library/st_binary macros' combine steps -- for whatever generated plc's C headers for a target's own srcs/hdrs. Read by _st_library_stub_source (see st/private/library_stubs.bzl) to scope {external} stub generation to exactly that target's own srcs/hdrs, using the same already-generated headers rather than regenerating them.",
    fields = {
        "headers_dir": "The directory generate_st_headers produced for this target's own srcs/hdrs (a single File, not a depset).",
        "sources": "depset of this target's own ST source Files (srcs/hdrs) headers_dir was generated from.",
    },
)

StLibraryStubSourceInfo = provider(
    doc = "Set by the private rule generating a target's __attribute__((weak)) stub .c source for its own {external} FUNCTION/FUNCTION_BLOCK declarations (see st/private/library_stubs.bzl). A plain rule reading `library`'s StHeadersInfo -- not an aspect -- so it only ever needs the plc toolchain, never a C++ one (kept separate from the rule that compiles stub_c, which needs a C++ toolchain but not plc's).",
    fields = {
        "stub_c": "The generated stub .c File, or None if the target declared no {external} POUs (or doesn't carry StHeadersInfo at all).",
        "headers_dir": "The same headers_dir stub_c was generated from (for compiling stub_c against it), or None if stub_c is None.",
    },
)

StLibraryStubsInfo = provider(
    doc = "Set by st_library_stubs_aspect (see st/private/library_stubs.bzl) on the st_library target it's applied to.",
    fields = {
        "cc_info": "A CcInfo linking in a __attribute__((weak)) zero-value stub for each {external} FUNCTION/FUNCTION_BLOCK declared in the target's own srcs/hdrs, or None if it declared none.",
    },
)

def create_st_compilation_context(interfaces = depset(), sources = depset()):
    return StCompilationContext(interfaces = interfaces, sources = sources)

def create_st_linking_context(objects = depset()):
    return StLinkingContext(objects = objects)

def merge_st_infos(st_infos):
    """Merges the compilation and linking contexts of st_infos, mirroring cc_common.merge_cc_infos."""
    return StInfo(
        compilation_context = create_st_compilation_context(
            interfaces = depset(transitive = [info.compilation_context.interfaces for info in st_infos]),
            sources = depset(transitive = [info.compilation_context.sources for info in st_infos]),
        ),
        linking_context = create_st_linking_context(
            objects = depset(transitive = [info.linking_context.objects for info in st_infos]),
        ),
    )
