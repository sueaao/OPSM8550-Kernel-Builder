#!/usr/bin/env bash
# Compose the exact FinaSU release with every supported SUSFS ABI snapshot.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/finasu-release.sh
. "$SCRIPT_DIR/../lib/finasu-release.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
git init -q "$fixture/FinaSU"
git -C "$fixture/FinaSU" remote add origin "${FINASU_TEST_SOURCE:-https://github.com/LyraVoid/FinaSU.git}"
git -C "$fixture/FinaSU" fetch -q --depth=1 origin "$FINASU_COMMIT"
git -C "$fixture/FinaSU" checkout -q --detach FETCH_HEAD
git init -q "$fixture/susfs"
git -C "$fixture/susfs" remote add origin "${FINASU_TEST_SUSFS_SOURCE:-https://gitlab.com/simonpunk/susfs4ksu.git}"
for ref in gki-android13-5.10 gki-android13-5.15 gki-android14-5.15 gki-android14-6.1; do
  commit="$(finasu_susfs_commit "$ref")"
  git -C "$fixture/susfs" fetch -q --depth=1 origin "$commit"
  git -C "$fixture/susfs" checkout -q --detach FETCH_HEAD
  python3 "$SCRIPT_DIR/finasu-features-test.py" "$fixture/FinaSU" "$fixture/susfs" "$ref" "$commit"
done
