"""Shared helper for generating plc's C headers for a set of ST sources."""

def generate_st_headers(ctx, compiler, sources, dep_interfaces, rule_kind):
    """Runs plc --generate-headers over `sources`, returning a directory (one
    generated .h per compiled module, named after that module, plus a
    dependencies.plc.h stub) usable as a compilation context's `includes`.

    plc's own header template unconditionally #includes <dependencies.plc.h>
    but never emits that file itself, so this also drops in a stub for it
    alongside plc's own output -- it must land in the same directory as the
    generated .h files since they share one -I include path.
    """
    headers_dir = ctx.actions.declare_directory(ctx.label.name + "_headers")

    header_args = ctx.actions.args()
    header_args.add(compiler.path)
    header_args.add_all(sources)
    header_args.add_all(dep_interfaces, before_each = "-i")
    header_args.add("--generate-headers")
    header_args.add("--header-output", headers_dir.path)

    generate_headers_script = ctx.actions.declare_file(ctx.label.name + "_generate_headers.sh")
    ctx.actions.write(
        output = generate_headers_script,
        content = """#!/usr/bin/env bash
set -eu
"$@"
printf '// Stub for plc-generated headers, which unconditionally #include this;\\n// left empty as {rule_kind} has no extra dependency declarations to add.\\n' \\
    > "{headers_dir}/dependencies.plc.h"
""".format(headers_dir = headers_dir.path, rule_kind = rule_kind),
        is_executable = True,
    )

    ctx.actions.run(
        executable = generate_headers_script,
        arguments = [header_args],
        inputs = depset([compiler] + sources, transitive = [dep_interfaces]),
        outputs = [headers_dir],
        mnemonic = "StGenerateHeaders",
        progress_message = "Generating C headers for %{label}",
    )
    return headers_dir
