#!/usr/bin/env bash
# Builds //third_party/rusty:plc and publishes it as a GitHub Release asset:
# a plc-linux-<arch>.tar.gz bundling plc with its runtime .so deps (plc uses
# a $ORIGIN rpath -- see rusty.BUILD.bazel -- so it only runs standalone once
# they're extracted alongside it).
#
# Usage: plc_compiler/release.sh <tag>
#
# Requires: bazel, ldd, a `gh` CLI authenticated with release-write access.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <tag>" >&2
    exit 1
fi
tag="$1"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

if [[ "$(uname -s)" != "Linux" ]]; then
    echo "error: this only builds Linux binaries (host is $(uname -s))" >&2
    exit 1
fi

case "$(uname -m)" in
    x86_64) arch=x86_64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    *)
        echo "error: unsupported host architecture $(uname -m)" >&2
        exit 1
        ;;
esac

echo "Building //third_party/rusty:plc for linux-$arch..." >&2
bazel build //third_party/rusty:plc

built_plc="$(bazel cquery --output=files //third_party/rusty:plc 2>/dev/null)"
if [[ -z "$built_plc" ]]; then
    echo "error: could not resolve the built plc binary's output path" >&2
    exit 1
fi

echo "Discovering plc's runtime library dependencies..." >&2
if ldd "$built_plc" | grep -q "not found"; then
    echo "error: plc has unresolved runtime dependencies:" >&2
    ldd "$built_plc" | grep "not found" >&2
    exit 1
fi
bundled_libs=()
while IFS= read -r lib_path; do
    case "$lib_path" in
        /lib/* | /lib64/* | /usr/lib/*) continue ;; # assumed present on any target Linux system
    esac
    bundled_libs+=("$lib_path")
done < <(ldd "$built_plc" | grep -oE '/\S+\.so(\.[0-9]+)*')
if [[ ${#bundled_libs[@]} -eq 0 ]]; then
    echo "error: found no non-system runtime libraries to bundle -- expected at least libllvm_wrapper.so" >&2
    exit 1
fi
echo "Bundling: ${bundled_libs[*]}" >&2

asset_name="plc-linux-${arch}"
staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT
bundle_dir="$staging_dir/$asset_name"
mkdir -p "$bundle_dir"
cp "$built_plc" "$bundle_dir/plc"
chmod +x "$bundle_dir/plc"
for lib_path in "${bundled_libs[@]}"; do
    cp "$lib_path" "$bundle_dir/"
done

echo "Sanity-checking the bundle runs standalone..." >&2
"$bundle_dir/plc" --version >/dev/null

archive_path="$staging_dir/$asset_name.tar.gz"
tar -C "$staging_dir" -czf "$archive_path" "$asset_name"

if gh release view "$tag" >/dev/null 2>&1; then
    echo "Uploading $asset_name.tar.gz to existing release $tag..." >&2
    gh release upload "$tag" "$archive_path" --clobber
else
    echo "Creating release $tag with $asset_name.tar.gz..." >&2
    gh release create "$tag" "$archive_path" --title "$tag" --generate-notes
fi

echo "Published $asset_name.tar.gz to release $tag." >&2
