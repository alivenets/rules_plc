"""Providers shared by the ST rules.

StInfo is structured like CcInfo: a compilation context (what a target exposes
to dependents at compile time) plus a linking context (what a target
contributes to the final link), with a merge helper mirroring
cc_common.merge_cc_infos.
"""

StCompilationContext = provider(
    doc = "Interface files a target exposes to dependents at compile time.",
    fields = {
        "interfaces": "depset of interface Files (compiled srcs plus declaration-only hdrs): this target's plus all transitive deps'.",
    },
)

StLinkingContext = provider(
    doc = "Objects a target contributes to the final link.",
    fields = {
        "objects": "depset of .o Files: this target's compiled object plus all transitive deps'.",
        "cc_info": "CcInfo (or None) for native libraries implementing this target's (or its transitive deps') {external} declarations.",
    },
)

StInfo = provider(
    doc = "Compiled ST library: a compilation context and a linking context.",
    fields = {
        "compilation_context": "An StCompilationContext.",
        "linking_context": "An StLinkingContext.",
    },
)

def create_st_compilation_context(interfaces = depset()):
    return StCompilationContext(interfaces = interfaces)

def create_st_linking_context(objects = depset(), cc_info = None):
    return StLinkingContext(objects = objects, cc_info = cc_info)

def merge_st_infos(st_infos):
    """Merges the compilation and linking contexts of st_infos, mirroring cc_common.merge_cc_infos."""
    cc_infos = [info.linking_context.cc_info for info in st_infos if info.linking_context.cc_info != None]
    return StInfo(
        compilation_context = create_st_compilation_context(
            interfaces = depset(transitive = [info.compilation_context.interfaces for info in st_infos]),
        ),
        linking_context = create_st_linking_context(
            objects = depset(transitive = [info.linking_context.objects for info in st_infos]),
            cc_info = cc_common.merge_cc_infos(cc_infos = cc_infos) if cc_infos else None,
        ),
    )
