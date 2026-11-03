#!/sbin/sh
# Shared by AnyKernel's recovery mounts and boot partition selection.
# Newer recoveries may expose androidboot.* only in /proc/bootconfig.
normalize_slot() {
  case "$1" in
    a|_a) echo _a ;;
    b|_b) echo _b ;;
    *) return 1 ;;
  esac
}

for property in ro.boot.slot_suffix ro.boot.slot; do
  slot=$(getprop "$property" 2>/dev/null)
  if normalize_slot "$slot"; then
    exit 0
  fi
done

# Match complete keys/values, accepting bootconfig's optional spaces/quotes.
# Never infer a slot from partition existence: both boot_a and boot_b exist.
for boot_file in /proc/cmdline /proc/bootconfig; do
  [ -r "$boot_file" ] || continue
  slot=$(awk '
    {
      gsub(/[[:space:]]*=[[:space:]]*/, "=")
      gsub(/"/, "")
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^androidboot\.slot(_suffix)?=(_?a|_?b)$/) {
          sub(/^[^=]*=/, "", $i)
          print $i
          exit
        }
      }
    }
  ' "$boot_file")
  if normalize_slot "$slot"; then
    exit 0
  fi
done
exit 1
