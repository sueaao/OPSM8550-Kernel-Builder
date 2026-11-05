#!/usr/bin/env bash
# A version label is required even when two Android branches share one commit.
android_build_variant() {
  case "$1" in
    0) ;;
    1)
      case "$2" in
        16|17) printf 'A%s\n' "$2" ;;
        *) echo '::error::Android batch builds require Android version 16 or 17.' >&2; return 1 ;;
      esac
      ;;
    *) echo "::error::Invalid Android batch flag: $1" >&2; return 1 ;;
  esac
}
