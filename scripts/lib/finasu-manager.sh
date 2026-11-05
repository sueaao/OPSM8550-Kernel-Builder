#!/usr/bin/env bash
# FinaSU release-manager identity. Sourced, not executed.
# shellcheck source=finasu-release.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/finasu-release.sh"

configure_finasu_manager() {
  [[ "$KSU_TYPE" == FinaSU* ]] || return 0

  # Mirror upstream's release workflow. Kbuild selects slot 2 as the trusted
  # FinaSU identity only when it is explicitly marked as a release key.
  MAKE_ARGS+=(
    "KSU_EXPECTED_SIZE2=$FINASU_MANAGER_CERT_SIZE"
    "KSU_EXPECTED_HASH2=$FINASU_MANAGER_CERT_SHA256"
    KSU_SECOND_SIGNATURE_RELEASE=1
  )
  echo "[config] FinaSU release manager certificate: $FINASU_MANAGER_CERT_SHA256 ($FINASU_MANAGER_CERT_SIZE bytes)"
}

verify_finasu_manager_binary() {
  local image="$1"
  local proof="$2"

  rm -f "$proof"
  if ! strings "$image" | grep -Fx "$FINASU_MANAGER_CERT_SHA256" >/dev/null; then
    echo "::error::FinaSU release manager certificate is missing from $image."
    return 1
  fi
  {
    echo "manager_package=me.yuki.fina"
    echo "manager_reference_release=$FINASU_RELEASE"
    echo "manager_apk_url=$FINASU_MANAGER_URL"
    echo "manager_apk_sha256=$FINASU_MANAGER_APK_SHA256"
    echo "manager_certificate_size=$FINASU_MANAGER_CERT_SIZE"
    echo "manager_certificate_sha256=$FINASU_MANAGER_CERT_SHA256"
    echo "image_sha256=$(sha256sum "$image" | awk '{print $1}')"
  } > "$proof"
  echo '[+] FinaSU release manager certificate verified in final Image.'
}
