"""Analysis-time check rule ensuring `interface_deps` are not re-exported."""

load("//st:providers.bzl", "StInfo")

def _check_impl(ctx):
    target = ctx.attr.target
    info = target[StInfo]

    # Collect basenames of interface files exposed by the target's StInfo
    interfaces = [f.basename for f in info.compilation_context.interfaces.to_list()]

    # Ensure iface.st from an interface_dep is NOT present in the exported interfaces
    for b in interfaces:
        if b == "iface.st":
            fail("interface_deps were re-exported via StInfo; expected them to be non-transitive")
    return [DefaultInfo()]

check_interface_rule = rule(
    implementation = _check_impl,
    attrs = {
        "target": attr.label(mandatory = True, providers = [StInfo]),
    },
)
