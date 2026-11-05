#!/usr/bin/env bash
# Run the real FinaSU signature matcher with our actual Kbuild arguments.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/finasu-release.sh
. "$SCRIPT_DIR/../lib/finasu-release.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
for commit in be19eb90b9c7b96f265c86b733aa0640a2839bdb 2d5786b9129a254a87ac358c8bec0203ccd53351; do
  for source_file in Kbuild manager/apk_sign.c; do
    mkdir -p "$fixture/$(dirname "$source_file")"
    curl --retry 3 --retry-all-errors -fLSs \
      "https://raw.githubusercontent.com/LyraVoid/FinaSU/$commit/kernel/$source_file" \
      -o "$fixture/$source_file"
  done
  python3 "$SCRIPT_DIR/finasu-manager-test.py" "$fixture"
done

# Exercise the exact paired release and downstream compatibility patch too.
git init -q "$fixture/release"
git -C "$fixture/release" fetch -q --depth=1 --no-tags \
  https://github.com/LyraVoid/FinaSU.git "$FINASU_COMMIT"
git -C "$fixture/release" checkout -q --detach FETCH_HEAD
python3 "$SCRIPT_DIR/finasu-manager-test.py" "$fixture/release/kernel"
python3 "$SCRIPT_DIR/finasu-integration-test.py" "$fixture/release"
curl --retry 3 --retry-all-errors -fLSs "$FINASU_MANAGER_URL" -o "$fixture/manager.apk"
python3 "$SCRIPT_DIR/finasu-release-test.py" "$fixture/manager.apk"
