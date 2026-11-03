#!/usr/bin/env bash
#
# Download the AOSP Clang toolchain requested in $CLANG_VERSION into
# toolchains/${CLANG_VERSION}. Intended to be skipped when the cache hits.
#
set -euo pipefail

: "${CLANG_VERSION:?CLANG_VERSION must be set}"

declare -A CLANG_URLS=(
  [clang-r584948]="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/b896c53892be0ae507473a9f3dce67907edf4965/clang-r584948.tar.gz"
  [clang-r596125]="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/b896c53892be0ae507473a9f3dce67907edf4965/clang-r596125.tar.gz"
  [clang-r416183b1]="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/2cddc8015b6a61bbcb8bb58e55d67e4e4b4db6d2/clang-r416183b1.tar.gz"
  [clang-r450784d]="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/c9c9d70ad5cb62dd761adccd87c34e8a35846a81/clang-r450784d.tar.gz"
  [clang-r487747c]="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/7154d3eddcb62ff7909a6ae2bf0c03e445e65bc4/clang-r487747c.tar.gz"
  [clang-r536225]="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/96266255abde668f1bf100bf2c47363b96b7a21e/clang-r536225.tar.gz"
  [clang-r547379]="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/9916fb51ccb914d62d35ad9a7b9b21d2ef046928/clang-r547379.tar.gz"
  [clang-r563880c]="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/9916fb51ccb914d62d35ad9a7b9b21d2ef046928/clang-r563880c.tar.gz"
)

URL="${CLANG_URLS[$CLANG_VERSION]:-}"
if [[ -z "$URL" ]]; then
  echo "::error::Unsupported clang version: $CLANG_VERSION"
  exit 1
fi

TARGET_DIR="toolchains/${CLANG_VERSION}"
mkdir -p toolchains

STAGING_DIR="$(mktemp -d "toolchains/.${CLANG_VERSION}.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
TMP_TAR="$STAGING_DIR/clang.tar.gz"

# Gitiles can return HTTP 200 with a truncated archive. Curl's transport
# retries cannot detect that, so retry the complete download/validation cycle.
for attempt in 1 2 3 4 5; do
  rm -f "$TMP_TAR"
  rm -rf "$STAGING_DIR/extracted"
  mkdir "$STAGING_DIR/extracted"
  echo "[clang] Download attempt $attempt/5: $CLANG_VERSION"
  if curl --retry 2 --retry-delay 3 --retry-all-errors \
       --connect-timeout 30 --max-time 1800 -fL "$URL" -o "$TMP_TAR" &&
     gzip -t "$TMP_TAR" &&
     tar -xzf "$TMP_TAR" -C "$STAGING_DIR/extracted" &&
     test -x "$STAGING_DIR/extracted/bin/clang" &&
     test -x "$STAGING_DIR/extracted/bin/llvm-nm" &&
     "$STAGING_DIR/extracted/bin/clang" --version > "$STAGING_DIR/version.txt"; then
    rm -rf "$TARGET_DIR"
    mv "$STAGING_DIR/extracted" "$TARGET_DIR"
    head -n 1 "$STAGING_DIR/version.txt"
    exit 0
  fi
  echo "::warning::AOSP Clang download or archive validation failed (attempt $attempt/5)."
  if [[ "$attempt" != 5 ]]; then
    sleep 3
  fi
done
echo "::error::Could not obtain a complete, usable AOSP Clang archive after 5 attempts."
exit 1
