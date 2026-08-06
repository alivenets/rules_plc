"""Public API for rules_plc: compiling IEC 61131-3 Structured Text with the rusty (plc) compiler."""

load("//st:private/library_stubs.bzl", _st_library_stub = "st_library_stub")
load("//st:private/st_binary.bzl", _st_binary = "st_binary")
load("//st:private/st_library.bzl", _st_library = "st_library")
load("//st:toolchain.bzl", _st_toolchain = "st_toolchain")

st_library = _st_library
st_binary = _st_binary
st_library_stub = _st_library_stub

# Consumers register their own plc compiler (see README.md) by wrapping it
# with this rule, then a native toolchain() targeting //st:toolchain_type.
st_toolchain = _st_toolchain
