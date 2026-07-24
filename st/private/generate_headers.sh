#!/usr/bin/env bash
# Runs plc's --generate-headers (the remaining args, after the headers
# output dir and the dependencies.plc.h to copy in) and drops a
# dependencies.plc.h stub into the same directory. plc's own header template
# unconditionally #includes <dependencies.plc.h> but never emits that file
# itself -- see st/private/headers.bzl.
set -eu

headers_dir="$1"
dependencies_plc_h="$2"
shift 2
"$@"

cp "$dependencies_plc_h" "$headers_dir/dependencies.plc.h"
