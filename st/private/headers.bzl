"""Shared helper for generating plc's C headers for a set of ST sources."""

def generate_st_headers(ctx, compiler, sources, dep_interfaces):
    """Runs plc --generate-headers over `sources`, returning a directory (one
    generated .h per compiled module, named after that module, plus a
    dependencies.plc.h stub) usable as a compilation context's `includes`.

    Requires the calling rule to declare a `GENERATE_HEADERS_ATTR` attrs
    (see st_library/st_binary's rule() attrs).
    """
    headers_dir = ctx.actions.declare_directory(ctx.label.name + "_st")

    header_args = ctx.actions.args()
    header_args.add(compiler.path)
    header_args.add_all(sources)
    header_args.add_all(dep_interfaces, before_each = "-i")
    header_args.add("--generate-headers")
    header_args.add("--header-output", headers_dir.path)

    ctx.actions.run(
        executable = ctx.file._generate_headers_sh,
        arguments = [headers_dir.path, ctx.file._dependencies_plc_h.path, header_args],
        inputs = depset([compiler, ctx.file._dependencies_plc_h] + sources, transitive = [dep_interfaces]),
        outputs = [headers_dir],
        mnemonic = "StGenerateHeaders",
        progress_message = "Generating C headers for %{label}",
    )
    return headers_dir

# Attach to a rule's attrs (via dict(..., **GENERATE_HEADERS_ATTR)) to make
# generate_st_headers usable from that rule's implementation.
GENERATE_HEADERS_ATTR = {
    "_generate_headers_sh": attr.label(
        default = Label("//st:private/generate_headers.sh"),
        allow_single_file = True,
    ),
    "_dependencies_plc_h": attr.label(
        default = Label("//st:private/dependencies.plc.h"),
        allow_single_file = True,
    ),
}
