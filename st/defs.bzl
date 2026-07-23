"""Public API for rules_plc: compiling IEC 61131-3 Structured Text with the rusty (plc) compiler."""

load("//st:private/st_binary.bzl", _st_binary = "st_binary")
load("//st:private/st_library.bzl", _st_library = "st_library")

st_library = _st_library
st_binary = _st_binary
