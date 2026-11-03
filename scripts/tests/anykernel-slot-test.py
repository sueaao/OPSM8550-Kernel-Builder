#!/usr/bin/env python3
"""Exercise the patched upstream recovery and boot-slot paths without a device."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

scripts = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    tools = root / "tools"
    tools.mkdir()
    update = root / "update-binary"
    core = tools / "ak3-core.sh"
    for source, destination in (("update-binary", update), ("ak3-core.sh", core)):
        shutil.copyfile(scripts / "tests/fixtures/anykernel-slot" / source, destination)
        destination.chmod(0o755)
    patch = '. "$1"; patch_anykernel_slot_detection "$2" "$3" "$4"'
    command = ["bash", "-c", patch, "slot-test", str(scripts / "lib/anykernel-helpers.sh"),
               str(update), str(core), str(scripts / "templates/detect-slot.sh")]
    subprocess.run(command, check=True)
    before = update.read_bytes(), core.read_bytes()
    subprocess.run(command, check=True)
    assert before == (update.read_bytes(), core.read_bytes()), "patch must be idempotent"
    assert core.stat().st_mode & 0o777 == 0o755

    # Substitute only the read paths in the test copy; production has no
    # environment-variable override for boot metadata or slot selection.
    detector = tools / "detect-slot.sh"
    detector.write_text(detector.read_text().replace("/proc/cmdline", str(root / "cmdline"))
                        .replace("/proc/bootconfig", str(root / "bootconfig")))
    getprop = tools / "getprop"
    getprop.write_text('''#!/bin/sh
case "$1" in
  ro.boot.slot_suffix) printf '%s' "$TEST_SUFFIX" ;;
  ro.boot.slot) printf '%s' "$TEST_SLOT" ;;
esac
''')
    getprop.chmod(0o755)
    cases = [
        ("_a", "", "", "", "_a"),
        ("", "b", "", "", "_b"),
        ("a", "", "", "", "_a"),
        ("", "", "quiet androidboot.slot_suffix=_b other=1", "", "_b"),
        ("", "", "androidboot.slot=a", "", "_a"),
        ("", "", "", 'androidboot.slot_suffix = "_a"\n', "_a"),
        ("", "", "", 'androidboot.slot = "b"\n', "_b"),
        ("", "", "", 'androidboot.slot_suffix=_b\n', "_b"),
        ("normal", "invalid", "", 'androidboot.slot_suffix = "_b"', "_b"),
        ("_b", "a", "androidboot.slot=a", 'androidboot.slot="a"', "_b"),
        ("", "", "notandroidboot.slot=a androidboot.slot_suffix=_bad", "", ""),
        ("_c", "0", "", 'androidboot.slot_suffix="_ab"', ""),
        ("", "", "", "", ""),
    ]
    for suffix, slot, cmdline, bootconfig, expected in cases:
        (root / "cmdline").write_text(cmdline)
        (root / "bootconfig").write_text(bootconfig)
        env = dict(os.environ, AKHOME=str(root), PATH=f"{tools}:{os.environ['PATH']}",
                   TEST_SUFFIX=suffix, TEST_SLOT=slot)
        recovery = subprocess.run(["bash", "-c", '. "$1"; find_slot', "test", str(update)],
                                  env=env, text=True, capture_output=True)
        assert recovery.stdout.strip() == expected, (suffix, slot, cmdline, bootconfig, recovery)
        boot = subprocess.run(["bash", "-c", '''
abort() { echo "$*" >&2; exit 97; }
IS_SLOT_DEVICE=1
SLOT_SELECT=active
. "$1"
setup_ak
printf '%s' "$SLOT"
''', "test", str(core)], env=env, text=True, capture_output=True)
        if expected:
            assert boot.returncode == 0 and boot.stdout == expected, boot
        else:
            assert boot.returncode == 97 and not boot.stdout, boot
    # Missing metadata must also abort; never choose a default slot.
    (root / "bootconfig").unlink()
    (root / "cmdline").unlink()
    result = subprocess.run(["sh", str(detector)], env=env, capture_output=True)
    assert result.returncode != 0 and not result.stdout
    core.write_text(core.read_text().replace('SLOT=$(sh', 'CHANGED=$(sh'))
    result = subprocess.run(command, capture_output=True)
    assert result.returncode != 0, "unrecognized upstream drift must fail"

print("PASS: recovery/boot slot detection, bootconfig fallback, invalid/missing metadata, patch drift")
