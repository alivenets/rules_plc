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

In addition, plc emits each POU's struct as an anonymous
`typedef struct { ... } NAME;` block ordered by source, which fails to
compile as C when one such block references a later-defined one via a
pointer. This script post-processes each generated header to give every
struct a matching tag, and renders forward `typedef struct NAME NAME;`
declarations for all of them into dependencies.plc.h so the tag is in
scope before the struct body is seen.

It also normalises C identifier casing to match ST's case-insensitive
semantics: plc emits identifiers with whatever surface spelling appears at
each occurrence, so a type defined as `ETH_X_IFMIB_T` but referenced as
`ETH_X_IfMib_T` in the .st source ends up as two distinct C identifiers.
The canonical spelling (the one from the `typedef ... } NAME;` line) is
chosen and every case-variant reference is rewritten to match it.

Usage: generate_headers.py <headers_dir> <dependencies_plc_h_template>
    <comma_separated_auto_include_names> <plc_binary> [plc_args...]
"""

import os
import re
import subprocess
import sys

import jinja2

# A plc-emitted POU struct: `typedef struct { <body> } NAME;`. plc never
# nests structs, unions, or enums in these headers, so a simple non-greedy
# `\{[^{}]*\}` match on the body is enough.
_TYPEDEF_STRUCT_RE = re.compile(
    r"typedef\s+struct\s*\{(?P<body>[^{}]*)\}\s*(?P<name>[A-Za-z_]\w*)\s*;",
    re.DOTALL,
)

# Same shape but after tagging, with a struct tag between `struct` and `{`.
_TAGGED_STRUCT_RE = re.compile(
    r"typedef\s+struct\s+(?P<tag>[A-Za-z_]\w*)\s*\{(?P<body>[^{}]*)\}\s*(?P<alias>[A-Za-z_]\w*)\s*;",
    re.DOTALL,
)

# One field declaration line inside a struct body: leading whitespace, then
# the first identifier (the type token), then the rest of the line.
_FIELD_LINE_RE = re.compile(r"(?m)^([ \t]+)([A-Za-z_]\w*)(.*)$")


def add_struct_tags(header_path):
    """Rewrite anonymous `typedef struct { ... } NAME;` blocks in-place to
    `typedef struct NAME { ... } NAME;`. Returns the list of NAMEs found."""
    with open(header_path) as f:
        text = f.read()
    names = []

    def replace(match):
        name = match["name"]
        names.append(name)
        return f"typedef struct {name} {{{match['body']}}} {name};"

    new_text = _TYPEDEF_STRUCT_RE.sub(replace, text)
    if new_text != text:
        with open(header_path, "w") as f:
            f.write(new_text)
    return names


def normalise_field_type_case(header_path, canonical_map):
    """Rewrite the type token (first identifier) on every field-decl line
    inside every tagged struct body, using canonical_map (lowercase name ->
    canonical spelling). Field names (second identifier) are untouched."""
    with open(header_path) as f:
        text = f.read()

    def rewrite_field(match):
        indent, first, rest = match.groups()
        canonical = canonical_map.get(first.lower())
        if canonical is not None and canonical != first:
            first = canonical
        return f"{indent}{first}{rest}"

    def rewrite_body(match):
        tag = match["tag"]
        alias = match["alias"]
        new_body = _FIELD_LINE_RE.sub(rewrite_field, match["body"])
        return f"typedef struct {tag} {{{new_body}}} {alias};"

    new_text = _TAGGED_STRUCT_RE.sub(rewrite_body, text)
    if new_text != text:
        with open(header_path, "w") as f:
            f.write(new_text)


def main():
    headers_dir, template_path, auto_include_names, *plc_command = sys.argv[1:]

    subprocess.run(plc_command, check=True)

    header_paths = [
        os.path.join(headers_dir, entry)
        for entry in sorted(os.listdir(headers_dir))
        if entry.endswith(".h") and entry != "dependencies.plc.h"
    ]
    forward_declarations = []
    for path in header_paths:
        forward_declarations.extend(add_struct_tags(path))
    forward_declarations = list(dict.fromkeys(forward_declarations))
    canonical_map = {name.lower(): name for name in forward_declarations}
    for path in header_paths:
        normalise_field_type_case(path, canonical_map)

    with open(template_path) as f:
        template = jinja2.Template(f.read(), keep_trailing_newline=True)

    auto_includes = auto_include_names.split(",") if auto_include_names else []
    with open(f"{headers_dir}/dependencies.plc.h", "w") as f:
        f.write(
            template.render(
                auto_includes=auto_includes,
                forward_declarations=forward_declarations,
            )
        )


if __name__ == "__main__":
    main()
