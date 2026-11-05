#!/usr/bin/env python3
"""Exercise the real pinned cleanup function and preinit artifact gates."""
import os
from pathlib import Path
import re
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]).resolve()
test_dir = Path(__file__).resolve().parent
helper = test_dir.parent / "lib/finasu-integration.sh"


def apply_patch(repo, expect_success=True):
    result = subprocess.run([
        "bash", "-c", '. "$1"; KSU_TYPE=FinaSU; KSU_REPO_DIR="$2"; apply_finasu_compat',
        "finasu-integration-test", str(helper), str(repo),
    ], capture_output=True, text=True)
    assert (result.returncode == 0) == expect_success, result.stdout + result.stderr


with tempfile.TemporaryDirectory() as temporary:
    fixture = Path(temporary)
    repo = fixture / "FinaSU"
    subprocess.run(["git", "-c", "advice.detachedHead=false", "clone", "-q", "--shared", str(source), str(repo)], check=True)
    original = (repo / "kernel/feature/netisolate.c").read_text()
    apply_patch(repo)
    patched = (repo / "kernel/feature/netisolate.c").read_text()
    apply_patch(repo)
    assert (repo / "kernel/feature/netisolate.c").read_text() == patched

    # Compile the real upstream exit function with its real 2064-byte UAPI
    # structure. An opaque publisher prevents the optimizer hiding the stack
    # temporary. The patched function must fit within the kernel's 2 KiB limit
    # and preserve stop -> publish disabled -> uninstall -> clear ordering.
    include = fixture / "linux"
    include.mkdir()
    (include / "types.h").write_text(
        "#include <stdint.h>\ntypedef uint32_t __u32; typedef uint64_t __u64;\n"
        "typedef uint16_t __u16; typedef uint8_t __u8;\n")
    shutil.copy(repo / "kernel/include/uapi/netisolate.h", fixture / "netisolate.h")
    publisher = fixture / "publisher.c"
    publisher.write_text('''
#include <assert.h>
#include "netisolate.h"
extern int stage;
void ni_publish_locked(const struct ksu_netisolate_policies *p) {
    assert(stage++ == 2);
    assert(!p->enabled && !p->count && !p->supported_flags && !p->reserved);
    for (int i = 0; i < KSU_NETISOLATE_MAX_POLICIES; ++i)
        assert(!p->policies[i].uid && !p->policies[i].flags);
}
''')
    for corrected, text in ((False, original), (True, patched)):
        function = re.search(r"void ksu_netisolate_exit\(void\)\n\{.*?\n\}", text, re.S).group()
        harness = fixture / "exit.c"
        harness.write_text('''
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include "netisolate.h"
int stage;
static int ni_lifecycle_lock;
static bool ni_stopping, ni_supported = true, ni_compat_supported = true;
static void mutex_lock(int *p) { assert(stage++ == 0); }
#define WRITE_ONCE(var, value) do { assert(stage++ == 1); (var) = (value); } while (0)
void ni_publish_locked(const struct ksu_netisolate_policies *p);
static int ni_uninstall_hooks_locked(void) { assert(stage++ == 3); return 0; }
static void ni_clear_events_locked(void) { assert(stage++ == 4); }
static void mutex_unlock(int *p) { assert(stage++ == 5); }
#define pr_err(...) fprintf(stderr, __VA_ARGS__)
''' + function + '''
int main(void) {
    ksu_netisolate_exit();
    assert(stage == 6 && ni_stopping && !ni_supported && !ni_compat_supported);
}
''')
        result = subprocess.run([
            *shlex.split(os.environ.get("CC", "cc")), "-O2", "-std=gnu11",
            "-Wframe-larger-than=2048", "-Werror", "-I", str(fixture),
            str(harness), str(publisher), "-o", str(fixture / "exit"),
        ], capture_output=True, text=True)
        assert (result.returncode == 0) == corrected, result.stderr
        if corrected:
            subprocess.run([str(fixture / "exit")], check=True)
        else:
            assert "frame" in result.stderr.lower() and "2048" in result.stderr, result.stderr
    # Refuse unexpected source drift instead of fuzz-applying the patch.
    (repo / "kernel/feature/netisolate.c").write_text(patched.replace("    WRITE_ONCE(ni_stopping, true);", "    ni_stopping = true;"))
    apply_patch(repo, expect_success=False)
    subprocess.run(["git", "-C", str(repo), "-c", "user.name=fixture",
                    "-c", "user.email=fixture@example.invalid", "commit",
                    "-q", "--allow-empty", "-m", "unreviewed revision"], check=True)
    apply_patch(repo, expect_success=False)

    # Reject missing, wrong-architecture, unembedded and incomplete artifacts.
    kernel = fixture / "kernel"
    preinit = kernel / "out/drivers/kernelsu/preinit"
    preinit.mkdir(parents=True)
    proof, image = fixture / "proof.txt", fixture / "Image"
    runner = bytearray(64)
    runner[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<HHIQ", runner, 16, 2, 183, 1, 0x400000)
    for case in ("missing", "wrong-arch", "missing-blob", "missing-image-runner", "valid"):
        data = bytearray(runner)
        if case == "wrong-arch":
            struct.pack_into("<H", data, 18, 62)
        (preinit / "runner.elf").write_bytes(data)
        (preinit / "blob.o").write_bytes(b"blob" if case == "missing-blob" else b"blob" + data)
        image.write_bytes(b"kernel" if case == "missing-image-runner" else b"kernel" + data)
        if case == "missing":
            (preinit / "runner.elf").unlink()
        result = subprocess.run([
            "bash", "-c", '. "$1"; verify_finasu_preinit_binary "$2" "$3" "$4"',
            "finasu-integration-test", str(helper), str(kernel), str(proof), str(image),
        ], capture_output=True, text=True)
        assert (result.returncode == 0) == (case == "valid"), result.stdout + result.stderr
        if case != "valid":
            assert not proof.exists(), "A failed verification left a stale proof"
    assert "preinit_image_verified=true" in proof.read_text()

print("PASS: FinaSU guarded patch, cleanup ordering, 2 KiB stack limit, and preinit artifact gates")
