#!/usr/bin/env bash
# Built-in integration checks for the reviewed FinaSU release.
# shellcheck source=finasu-release.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/finasu-release.sh"

apply_finasu_compat() {
  [[ "$KSU_TYPE" == FinaSU ]] || return 0
  local patch_file
  if [[ "$(git -C "$KSU_REPO_DIR" rev-parse HEAD)" != "$FINASU_COMMIT" ]]; then
    echo "::error::FinaSU compatibility patch requires $FINASU_RELEASE ($FINASU_COMMIT)."
    return 1
  fi
  patch_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../patches/finasu-netisolate-stack.patch"
  if ! git -C "$KSU_REPO_DIR" apply --reverse --check "$patch_file" 2>/dev/null; then
    git -C "$KSU_REPO_DIR" apply --check "$patch_file" || return 1
    git -C "$KSU_REPO_DIR" apply "$patch_file" || return 1
  fi
  echo '[+] FinaSU netisolate cleanup uses a read-only empty policy instead of a 2064-byte stack temporary.'
}

# Check the real ARM64 runner and its embedded bytes, including the final Image
# when present. A driver build that silently omits preinit must not pass.
verify_finasu_preinit_binary() {
  local kernel_root="$1" proof="$2" image="${3:-}"
  local driver_dir=drivers
  [[ ! -d "$kernel_root/common/drivers" ]] || driver_dir=common/drivers
  rm -f "$proof"
  python3 - "$kernel_root/out/$driver_dir/kernelsu/preinit" "$proof" "$image" <<'PY'
import hashlib
from pathlib import Path
import struct
import sys

directory, proof, image = sys.argv[1:]
try:
    runner = (Path(directory) / 'runner.elf').read_bytes()
    blob = (Path(directory) / 'blob.o').read_bytes()
except OSError as error:
    sys.exit(f'::error::FinaSU preinit artifact unavailable: {error}')
if (len(runner) < 64 or runner[:6] != b'\x7fELF\x02\x01'
        or struct.unpack_from('<HHI', runner, 16) != (2, 183, 1)
        or struct.unpack_from('<Q', runner, 24)[0] == 0):
    sys.exit('::error::FinaSU preinit runner is not an ARM64 executable.')
if runner not in blob:
    sys.exit('::error::FinaSU preinit blob does not contain the runner.')
if image and runner not in Path(image).read_bytes():
    sys.exit('::error::FinaSU final Image does not contain the preinit runner.')
Path(proof).write_text(
    'preinit_runner_arch=arm64\n'
    f'preinit_runner_sha256={hashlib.sha256(runner).hexdigest()}\n'
    f'preinit_runner_size={len(runner)}\n'
    f'preinit_image_verified={str(bool(image)).lower()}\n')
print('[+] FinaSU preinit runner verified' + (' in final Image.' if image else '.'))
PY
}
