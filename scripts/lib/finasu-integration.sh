#!/usr/bin/env bash
# Built-in integration checks for the reviewed FinaSU release.
# shellcheck source=finasu-release.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/finasu-release.sh"

apply_finasu_compat() {
  [[ "$KSU_TYPE" == FinaSU* ]] || return 0
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

verify_finasu_susfs_inputs() {
  local source_dir="$1" susfs_dir="$2" ref="$3" commit="$4"
  [[ "$(git -C "$(dirname "$source_dir")" rev-parse HEAD)" == "$FINASU_COMMIT" ]] || return 1
  [[ "$commit" == "$(finasu_susfs_commit "$ref")" ]] || {
    echo '::error::FinaSU requires the reviewed per-KMI SUSFS patch set.'
    return 1
  }
  python3 - "$source_dir" "$susfs_dir/kernel_patches" <<'PY'
from pathlib import Path
import re
import sys

source, patches = map(Path, sys.argv[1:])
ten = (patches / 'KernelSU/10_enable_susfs_for_ksu.patch').read_text()
expected = set(re.findall(r'^\+(?:menu)?config (KSU_SUSFS\w*)', ten, re.M))
actual = set(re.findall(r'^(?:menu)?config (KSU_SUSFS\w*)', (source / 'Kconfig').read_text(), re.M))
if expected != actual:
    sys.exit('::error::FinaSU/SUSFS Kconfig interface differs from the reviewed release.')
commands = set(re.findall(r'^#define (CMD_SUSFS_\w+)', '\n'.join(
    line for line in (patches / 'include/linux/susfs_def.h').read_text().splitlines()
    if 'deprecated' not in line), re.M))
dispatch = (source / 'extension/susfs.c').read_text()
missing = [name for name in sorted(commands) if f'case {name}:' not in dispatch]
if missing:
    sys.exit('::error::FinaSU lacks SUSFS commands: ' + ', '.join(missing))
print('[+] FinaSU SUSFS options and command dispatch match the pinned patch set.')
PY
}

install_finasu_nomount() {
  local source_dir="$KSU_REPO_DIR/userspace/nomount/kernel/src"
  [[ "$(git -C "$KSU_REPO_DIR" rev-parse HEAD)" == "$FINASU_COMMIT" && "$NOMOUNT_COMMIT" == "$FINASU_COMMIT" ]] || return 1
  # These are the byte-identical v2.2.0 sources recorded in FinaSU's UPSTREAM.md.
  # Do not follow NoMount master: its wire ABI may outgrow the paired ksud.
  (
    cd "$source_dir" || exit 1
    sha256sum --check <<'SUMS'
25452d96684d066446fbd1b433f4fdeab1c5b0ade11701d9b46bb8dfb5acfc1b  nomount.c
8f15ffcb4b998d8a05219b793cf22c0e25a383296376fc49a331e07bc7c93766  nomount.h
1df7ad3589a282128f797f7a46b28aee315d080550aae26b681a898f11c7abc7  Kconfig
1191fe9ef8e2f3549419fd90a118fbe3d11fc02a04b6353bae0e81be27e03e62  Makefile
SUMS
  ) || return 1
  wire_nomount_source "$source_dir" "$NOMOUNT_REF" "$NOMOUNT_COMMIT"
  [[ "$NOMOUNT_VERSION" == 22 ]] || {
    echo '::error::FinaSU requires its vendored NoMount API v22 driver.'
    return 1
  }
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
