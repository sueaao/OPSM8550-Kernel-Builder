#!/usr/bin/env bash
# Merge verified matrix artifacts while retaining every Android/root variant.
set -euo pipefail
PACKAGE_ROOT="${1:-${GITHUB_WORKSPACE:?}/release-packages}"
ASSET_DIR="${2:-${GITHUB_WORKSPACE:?}/release-assets}"
NOTES_FILE="$ASSET_DIR/release-notes.md"
mkdir -p "$ASSET_DIR"
: > "$NOTES_FILE"
package_count=0
for package_dir in "$PACKAGE_ROOT"/kernel-package-*; do
  [[ -d "$package_dir" ]] || continue
  package_count=$((package_count + 1))
  artifact_name="$(basename "$package_dir")"
  build_variant="${artifact_name#"kernel-package-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}-"}"
  (
    cd "$package_dir"
    sha256sum --check SHA256SUMS
  )
  for file in "$package_dir"/*.zip "$package_dir"/Image-*; do
    destination="$ASSET_DIR/$(basename "$file")"
    if [[ -e "$destination" ]]; then
      echo "::error::Release asset name collision: $(basename "$file")"
      exit 1
    fi
    cp "$file" "$destination"
  done
  cp "$package_dir/build-info.json" "$ASSET_DIR/build-info-${build_variant}.json"
  sed "s/  build-info.json$/  build-info-${build_variant}.json/" \
    "$package_dir/SHA256SUMS" > "$ASSET_DIR/SHA256SUMS-${build_variant}"
  {
    echo "## ${build_variant}"
    echo
    tail -n +3 "$package_dir/release-notes.md"
    echo
  } >> "$NOTES_FILE"
done
if (( package_count == 0 )); then
  echo '::error::No build packages were downloaded for this workflow run.'
  exit 1
fi
