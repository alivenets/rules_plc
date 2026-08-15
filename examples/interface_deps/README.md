# interface_deps

Vendor-interface pattern: the vendor ships ST files carrying only
`{external}` declarations of the POUs its runtime provides, never the
bodies. Local builds resolve the missing bodies with a test-time stub
-- typically a `cc_library` reached through the st_binary's `cc_deps`
attribute. Production deployments upload only the ST files you wrote
to a remote plc, which already has the vendor's real runtime.

The `interface_deps` attribute (on `st_library` and `st_binary`) keeps
those two audiences straight in the exported `StInfo`:

- Sources reached via a dep's normal `deps` chain land in
  `StInfo.compilation_context.sources` -- the "owned" bucket, i.e.
  everything a downstream deployment rule should ship.
- Sources reached via a dep's `interface_deps` chain get demoted into
  `StInfo.compilation_context.interface_sources` -- the "vendor
  interface" bucket. Still visible to plc's `-i` at LOCAL compile time
  (for cross-library type resolution), never uploaded remotely.

Both buckets propagate transitively: a downstream library's regular
dep's `interface_sources` also lands in its own `interface_sources`,
so the "excluded from shipping" set stays intact however deep the
chain runs.

## Files

- `vendor_pump.st` -- the vendor's interface. A `{external}
  FUNCTION_BLOCK Pump` declaration, no body. Wrapped in a plain
  `st_library` because `interface_deps` needs an `StInfo` provider on
  the other end.
- `vendor_pump_stub.cc` -- local-only native impl of `Pump`. Wired
  into `:main` through `cc_deps`, so the object DOES link into the
  local test binary. Stands in for the vendor's real runtime.
- `plant.st` -- production code that instantiates `Pump`. Its
  `st_library` names `:vendor_pump` under `interface_deps`, NOT
  `deps` -- so `plant.st`'s exported
  `StInfo.compilation_context.sources` contains just `plant.st`, and
  its `interface_sources` contains `vendor_pump.st`.
- `main_program.st` -- entry point. Instantiates `Plant`.
- `remote_manifest.bzl` -- a small custom rule reading a target's
  `StInfo.compilation_context.sources` OR `.interface_sources`
  (selected by the `bucket` attr) and writing sorted basenames to
  one file. Stands in for whatever real "ship to remote plc" rule a
  project would author.
- `plant_owned_manifest.expected.txt` -- locks in the "owned" bucket
  contents for `:plant`: exactly `plant.st`, no `vendor_pump.st`.
- `plant_interfaces_manifest.expected.txt` -- locks in the
  "interfaces" bucket contents for `:plant`: exactly `vendor_pump.st`,
  no `plant.st`.

## Tests

- `main_test` -- a `cc_test` that both invokes `Plant` directly via
  the plc-generated header (proving the header propagation works
  through `interface_deps`, since the fused st_library's CcInfo still
  carries every underlying leaf's headers bundle) and runs the
  `:main` binary through runfiles, expecting a clean exit. Exercises
  end-to-end that the `interface_deps` split neither duplicates nor
  drops the `Pump` symbol at link time.
- `plant_owned_manifest_test` and `plant_interfaces_manifest_test` --
  assert that the `remote_manifest` output for `:plant` splits its
  sources exactly as documented above.
