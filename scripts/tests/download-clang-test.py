#!/usr/bin/env python3
"""Model HTTP-success truncation and verify retry/atomic toolchain installation."""
import io
import gzip
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile

downloader = Path(__file__).resolve().parents[1] / "download-clang.sh"
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    mocks = root / "bin"
    mocks.mkdir()
    valid = root / "valid.tar.gz"
    with tarfile.open(valid, "w:gz") as archive:
        for name in ("clang", "llvm-nm"):
            content = b"#!/bin/sh\necho test-clang\n"
            entry = tarfile.TarInfo(f"bin/{name}")
            entry.size, entry.mode = len(content), 0o755
            archive.addfile(entry, io.BytesIO(content))
    data = valid.read_bytes()
    (root / "truncated.tar.gz").write_bytes(data[:len(data) // 2])
    # gzip is valid, but its inner tar is incomplete.
    (root / "bad-tar.tar.gz").write_bytes(gzip.compress(b"not a tar archive"))
    with tarfile.open(root / "missing-tool.tar.gz", "w:gz"):
        pass
    (mocks / "curl").write_text('''#!/bin/sh
count=0
[ ! -f "$TEST_ROOT/count" ] || count=$(cat "$TEST_ROOT/count")
count=$((count + 1))
echo "$count" > "$TEST_ROOT/count"
while [ "$#" -gt 0 ]; do
  case "$1" in -o) output=$2; shift ;; esac
  shift
done
case "$TEST_MODE:$count" in
  transport:*) exit 22 ;;
  recover:1|truncated:*) archive=truncated ;;
  recover:2|bad-tar:*) archive=bad-tar ;;
  recover:3|missing-tool:*) archive=missing-tool ;;
  *) archive=valid ;;
esac
cp "$TEST_ROOT/$archive.tar.gz" "$output"
''')
    (mocks / "sleep").write_text("#!/bin/sh\nexit 0\n")
    for script in mocks.iterdir():
        script.chmod(0o755)
    for mode, attempts, success in (("recover", 4, True), ("valid", 1, True),
                                    ("truncated", 5, False), ("bad-tar", 5, False),
                                    ("missing-tool", 5, False), ("transport", 5, False)):
        target = root / "toolchains/clang-r584948"
        target.mkdir(parents=True, exist_ok=True)
        (target / "old-cache").write_text("preserve until replacement is ready")
        (root / "count").unlink(missing_ok=True)
        env = dict(os.environ, TEST_ROOT=str(root), TEST_MODE=mode, CLANG_VERSION="clang-r584948",
                   PATH=f"{mocks}:{os.environ['PATH']}")
        result = subprocess.run(["bash", str(downloader)], cwd=root, env=env,
                                text=True, capture_output=True)
        assert (result.returncode == 0) == success, result
        assert int((root / "count").read_text()) == attempts
        assert (target / "old-cache").exists() != success
        assert not list((root / "toolchains").glob(".*")), "staging files must be cleaned"

print("PASS: truncated HTTP-success archives, tar/tool validation, bounded retries, staged installation")
