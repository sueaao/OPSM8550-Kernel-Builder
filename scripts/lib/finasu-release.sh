#!/usr/bin/env bash
# Reviewed upstream release pair. Update source, APK digest and tests together.
# Variables are consumed by the scripts sourcing this metadata file.
# shellcheck disable=SC2034
FINASU_RELEASE=v1.4.5
FINASU_COMMIT=a839ce2d742f0f1450a3aad20bdc14bc060da840
FINASU_MANAGER_APK=FinaSU_v1.4.5_33168-release.apk
FINASU_MANAGER_URL="https://github.com/LyraVoid/FinaSU/releases/download/$FINASU_RELEASE/$FINASU_MANAGER_APK"
FINASU_MANAGER_APK_SHA256=edbe2e8fb860135ad0142d672ded2ee4327d70a06746d8d629645184f7eeaeb6
# Extracted from the verified APK v2 signing block; unchanged since v1.2.1.
FINASU_MANAGER_CERT_SIZE=0x02cc
FINASU_MANAGER_CERT_SHA256=2d89b50aaf1db013c2b6738f973f48b62ea21a3a8d7216bfec3521065d448458

# Same interfaces as FinaSU's documented android15-6.6 SUSFS reference
# (4a4cb1be85a4694372d3efb9420de69982eac29a), with per-KMI kernel patches.
# Later SUSFS revisions replace the SELinux interface and need a new review.
finasu_susfs_commit() {
  case "$1" in
    gki-android13-5.10) echo cbe3fe7b9fa599d316f68b08b06cde48218eaff5 ;;
    gki-android13-5.15) echo 86b5b10068459dedb545dc5db46a0f0254428eda ;;
    gki-android14-5.15) echo 10b4f2156470338a5db2040f3d85992c285aa595 ;;
    gki-android14-6.1) echo b57ed1998b82c4e3a2a81cdbf11172a560979c40 ;;
    *) echo "::error::No FinaSU-compatible SUSFS revision for $1" >&2; return 1 ;;
  esac
}
