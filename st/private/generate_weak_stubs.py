#!/usr/bin/env python3
"""Finds {external} FUNCTION/FUNCTION_BLOCK declarations (via plc's own AST,
not by re-parsing ST source ourselves) and emits a __attribute__((weak))
zero-value-returning stub for each, keyed off its already-generated C
prototype (see st/private/library_stubs.bzl).

A weak symbol is silently overridden by a strong (i.e. any ordinary, non-
weak) definition of the same name elsewhere in the final link -- such as a
real native implementation of an {external} declaration, linked in via any
ordinary cc_library dep. Linking these stubs in unconditionally means a
library missing (or not yet given) a native implementation still links and
runs -- as a no-op / zero value -- instead of failing at link time with an
undefined reference far from the actual mistake.

Usage: generate_weak_stubs.py <out.c> <headers_dir> <template> <compiler> <src>...
"""

import json
import os
import re
import subprocess
import sys

import jinja2


# A prototype line as plc's header generator emits it, e.g.
# "int32_t fast_double(int32_t x);" -- captures the return type (everything
# before the name) and the full "name(...)" signature tail separately.
def prototype_re(name):
    return re.compile(
        r"^(?P<return_type>[A-Za-z_][A-Za-z0-9_ *]*?)\s*"
        r"(?P<signature>\b" + re.escape(name) + r"\(.*\));$",
        re.MULTILINE,
    )


def module_of(file_path):
    return os.path.splitext(os.path.basename(file_path))[0]


def user_type_name(user_type):
    # user_type["data_type"] is a single-key tagged variant, e.g.
    # {"StructType": {"name": ..., "variables": [...]}} or {"SubRangeType":
    # {"name": ..., ...}} -- every variant carries a "name" field.
    ((_, variant),) = user_type["data_type"].items()
    return variant.get("name")


def referenced_type_names(pou):
    """Every type name pou's own signature references: its VAR_INPUT/
    VAR_OUTPUT/VAR_IN_OUT parameters, plus (for a FUNCTION) its return type.
    """
    names = set()

    ref = (pou.get("return_type") or {}).get("Reference")
    if ref:
        names.add(ref["referenced_type"])

    for variable_block in pou["variable_blocks"]:
        for variable in variable_block["variables"]:
            ref = (variable["data_type_declaration"] or {}).get("Reference")
            if ref:
                names.add(ref["referenced_type"])

    return names


def find_externals(compiler, sources):
    """Returns (externals, type_modules).

    `externals` is a list of (name, module, referenced_type_names) for
    every {external} FUNCTION/FUNCTION_BLOCK POU declared in `sources`
    themselves.

    `type_modules` maps every POU/DUT name declared in `sources` to the
    module (basename, no extension) that declares it -- used to resolve
    which header(s) an {external} declaration's own referenced types need.
    """
    units = json.loads(
        subprocess.run(
            [compiler, "--ast-json", *sources],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    )

    type_modules = {}
    externals = []
    for unit in units:
        module = module_of(unit["file"]["File"])
        for pou in unit["pous"]:
            type_modules[pou["name"]] = module
            if pou.get("linkage") == "External":
                externals.append((pou["name"], module, referenced_type_names(pou)))
        for user_type in unit.get("user_types", []):
            name = user_type_name(user_type)
            if name:
                type_modules[name] = module

    return externals, type_modules


def stub_body(return_type):
    if return_type == "void":
        return "{}"
    return f"{{ {return_type} __ret = {{0}}; return __ret; }}"


def main():
    out_path, headers_dir, template_path, compiler, *sources = sys.argv[1:]

    externals, type_modules = find_externals(compiler, sources)

    headers = {}

    def header_text(module):
        if module not in headers:
            header_path = os.path.join(headers_dir, module + ".h")
            if os.path.isfile(header_path):
                with open(header_path) as f:
                    headers[module] = f.read()
            else:
                headers[module] = None
        return headers[module]

    includes = []
    stubs = []
    for name, module, referenced_types in externals:
        text = header_text(module)
        if text is None:
            continue
        match = prototype_re(name).search(text)
        if not match:
            continue

        if module not in includes:
            includes.append(module)
        # The stub's own signature may reference other modules' types (e.g. a
        # FUNCTION_BLOCK-typed parameter/field) -- #include those too, so the
        # generated stub .c file actually has those types in scope. Only
        # types declared in `sources` (this library's own files) resolve to
        # a module here; anything else (e.g. from a dep, via -i) isn't
        # generated into this same headers_dir and can't be included this
        # way.
        for type_name in referenced_types:
            type_module = type_modules.get(type_name)
            if (
                type_module
                and type_module != module
                and type_module not in includes
                and header_text(type_module)
            ):
                includes.append(type_module)

        return_type = match.group("return_type").strip()
        stubs.append(
            {
                "return_type": return_type,
                "signature": match.group("signature"),
                "body": stub_body(return_type),
            }
        )

    with open(template_path) as f:
        template = jinja2.Template(f.read(), keep_trailing_newline=True)

    with open(out_path, "w") as f:
        f.write(template.render(includes=includes, stubs=stubs))


if __name__ == "__main__":
    main()
