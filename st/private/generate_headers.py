#!/usr/bin/env python3
"""Runs plc --generate-headers, then renders dependencies.plc.h (a Jinja2
template) into the same directory. plc's own header template unconditionally
#includes <dependencies.plc.h> but never emits that file itself.

dependencies.plc.h #includes each "auto-include" module's own generated
header, by relative (same-directory) path -- since every generated header
already #includes <dependencies.plc.h> unconditionally as its own first
include, this makes any of a library's own module headers pull those in
transitively, instead of requiring consumers to work out and apply the right
#include order themselves. Callers must only pass declaration-only modules
as auto-includes (e.g. hdrs/DUTs) -- a module that itself references *other*
modules in the same library risks an #include-order hazard if auto-included
this way (reached before its own type/struct definitions, while referencing
a type that isn't defined yet).

Usage: generate_headers.py <headers_dir> <dependencies_plc_h_template>
    <comma_separated_auto_include_names> <plc_binary> [plc_args...]
"""

import subprocess
import sys

import jinja2


def main():
    headers_dir, template_path, auto_include_names, *plc_command = sys.argv[1:]

    subprocess.run(plc_command, check=True)

    with open(template_path) as f:
        template = jinja2.Template(f.read(), keep_trailing_newline=True)

    auto_includes = auto_include_names.split(",") if auto_include_names else []
    with open(f"{headers_dir}/dependencies.plc.h", "w") as f:
        f.write(template.render(auto_includes=auto_includes))


if __name__ == "__main__":
    main()
