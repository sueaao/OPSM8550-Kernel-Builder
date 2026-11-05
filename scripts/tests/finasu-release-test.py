#!/usr/bin/env python3
"""Check the pinned release APK digest and its APK v2 signing certificate."""
import hashlib
from pathlib import Path
import ssl
import struct
import subprocess
import sys

test_dir = Path(__file__).resolve().parent
metadata = subprocess.check_output([
    "bash", "-c", '. "$1"; printf "%s\\n" "$FINASU_MANAGER_APK_SHA256" '
    '"$FINASU_MANAGER_CERT_SHA256" "$FINASU_MANAGER_CERT_SIZE"',
    "finasu-release-test", str(test_dir.parent / "lib/finasu-release.sh"),
], text=True).splitlines()
apk = Path(sys.argv[1]).read_bytes()
assert hashlib.sha256(apk).hexdigest() == metadata[0], "APK digest differs from reviewed release"
eocd = apk.rfind(b"PK\x05\x06")
assert eocd >= 0
central_directory = struct.unpack_from("<I", apk, eocd + 16)[0]
assert apk[central_directory - 16:central_directory] == b"APK Sig Block 42"
block_size = struct.unpack_from("<Q", apk, central_directory - 24)[0]
block_start = central_directory - block_size - 8
assert struct.unpack_from("<Q", apk, block_start)[0] == block_size


def length_prefixed(data):
    length = struct.unpack_from("<I", data)[0]
    assert length <= len(data) - 4
    return data[4:4 + length], data[4 + length:]


offset = block_start + 8
certificates = []
while offset < central_directory - 24:
    size, kind = struct.unpack_from("<QI", apk, offset)
    assert size >= 4 and offset + 8 + size <= central_directory - 24
    if kind == 0x7109871A:  # APK Signature Scheme v2
        signers, _ = length_prefixed(apk[offset + 12:offset + 8 + size])
        while signers:
            signer, signers = length_prefixed(signers)
            signed_data, _ = length_prefixed(signer)
            _, remainder = length_prefixed(signed_data)  # digests
            chain, _ = length_prefixed(remainder)
            certificate, _ = length_prefixed(chain)
            certificates.append(certificate)
    offset += 8 + size
assert len(certificates) == 1, "Expected one release signer"
cert = certificates[0]
assert len(cert) == int(metadata[2], 16)
assert hashlib.sha256(cert).hexdigest() == metadata[1]
assert cert == ssl.PEM_cert_to_DER_cert((test_dir / "fixtures/finasu-v1.2.1-cert.pem").read_text())
print("PASS: paired release APK digest and signing certificate")
