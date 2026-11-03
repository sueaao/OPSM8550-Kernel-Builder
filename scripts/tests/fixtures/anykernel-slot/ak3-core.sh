# Slot detection from osm0sis/AnyKernel3@020dfeccf9d7e962a48400fc94d3e451df92eead
setup_ak() {
  local blockfiles plistboot plistinit plistreco parttype name part mtdmount mtdpart mtdname target;

  # slot detection enabled by IS_SLOT_DEVICE=1 or auto (from anykernel.sh)
  case $IS_SLOT_DEVICE in
    1|auto)
      SLOT=$(getprop ro.boot.slot_suffix 2>/dev/null);
      [ "$SLOT" ] || SLOT=$(grep -o 'androidboot.slot_suffix=.*$' /proc/cmdline | cut -d\  -f1 | cut -d= -f2);
      if [ ! "$SLOT" ]; then
        SLOT=$(getprop ro.boot.slot 2>/dev/null);
        [ "$SLOT" ] || SLOT=$(grep -o 'androidboot.slot=.*$' /proc/cmdline | cut -d\  -f1 | cut -d= -f2);
        [ "$SLOT" ] && SLOT=_$SLOT;
      fi;
      [ "$SLOT" == "normal" ] && unset SLOT;
      if [ "$SLOT" ]; then
        if [ -d /postinstall/tmp -a ! "$SLOT_SELECT" ]; then
          SLOT_SELECT=inactive;
        fi;
        case $SLOT_SELECT in
          inactive)
            case $SLOT in
              _a) SLOT=_b;;
              _b) SLOT=_a;;
            esac;
          ;;
        esac;
      fi;
      if [ ! "$SLOT" -a "$IS_SLOT_DEVICE" == 1 ]; then
        abort "Unable to determine active slot. Aborting...";
      fi;
    ;;
  esac;

}
