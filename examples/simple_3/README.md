# simple

`hello`: a standalone `st_binary` (just `hello.st`'s `PROGRAM hello`), with
no library dependencies and no `srcs` of its own.

`hello_test.cc` runs the compiled `hello` executable (found via
`@bazel_tools//tools/cpp/runfiles`, added as `data`) and asserts on its
captured stdout, exercising the generated `FUNCTION main` entry point and
`hello`'s `{external} puts` binding end to end.
