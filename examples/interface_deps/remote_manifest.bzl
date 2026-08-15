"""remote_manifest: enumerate the ST files that would ship to a remote plc.

Consumes a target's StInfo (from //st:providers.bzl) and emits a single
sorted-basenames file for either bucket of its compilation context:

- `bucket = "owned"` selects StInfo.compilation_context.sources -- the
  "shippable" set (own srcs + regular deps' owned sources, transitively).
  Exactly what a deployment step should upload to a remote plc that
  already has the vendor's runtime.

- `bucket = "interfaces"` selects StInfo.compilation_context.interface_sources
  -- everything demoted via any interface_deps chain (vendor interfaces
  that must stay visible to plc's `-i` at LOCAL compile time for
  cross-library type resolution, but that the remote plc already has
  and does not need re-uploaded).

The rule intentionally emits a single File per invocation (rather than
two files under one target), so diff_test's `file2 = ":<rule_name>"`
resolves to that File unambiguously.
"""

load("@rules_plc//st:providers.bzl", "StInfo")

def _remote_manifest_impl(ctx):
    st_info = ctx.attr.target[StInfo]
    cctx = st_info.compilation_context
    files = cctx.sources if ctx.attr.bucket == "owned" else cctx.interface_sources

    names = sorted([f.basename for f in files.to_list()])
    out = ctx.actions.declare_file(ctx.label.name + ".txt")

    # Trailing newline so diff_test compares clean text, even when the
    # bucket is empty (empty content, no bytes).
    ctx.actions.write(
        output = out,
        content = "\n".join(names) + ("\n" if names else ""),
    )

    return [DefaultInfo(files = depset([out]))]

remote_manifest = rule(
    implementation = _remote_manifest_impl,
    attrs = {
        "target": attr.label(mandatory = True, providers = [StInfo]),
        "bucket": attr.string(mandatory = True, values = ["owned", "interfaces"]),
    },
    doc = "Writes a sorted basename list of one of a target's StInfo compilation-context source buckets ('owned' or 'interfaces') to a single output file.",
)
