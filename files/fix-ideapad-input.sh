#!/bin/sh
# Lenovo IdeaPad Slim 3 15ARP10 (83MM) - systemd sleep hook
# 1. pre: prevents spurious wakeups while the lid is closed (i8042 IRQ 1, ELAN touchpad GPIO 9, Wi-Fi GPP6).
# 2. post:
#    - If the lid is open, waits for the EC to settle and rebinds atkbd (serio0) and i2c_hid_acpi (ELAN06FA:00).
#    - If the system woke while the lid is still closed (e.g., AC plug/unplug), skips input rebind and sleeps 5s
#      to avoid an immediate re-suspend race condition (~100ms) that can lock up the EC/SoC.

case "$1" in
  pre)
    if [ -w /sys/devices/platform/i8042/serio0/power/wakeup ]; then
      echo "disabled" > /sys/devices/platform/i8042/serio0/power/wakeup 2>/dev/null || true
    fi
    if [ -w /sys/devices/platform/AMDI0010:01/i2c-1/i2c-ELAN06FA:00/power/wakeup ]; then
      echo "disabled" > /sys/devices/platform/AMDI0010:01/i2c-1/i2c-ELAN06FA:00/power/wakeup 2>/dev/null || true
    fi
    if grep -q "GPP6.*\*enabled" /proc/acpi/wakeup 2>/dev/null; then
      echo "GPP6" > /proc/acpi/wakeup 2>/dev/null || true
    fi
    ;;

  post)
    if grep -q "open" /proc/acpi/button/lid/LID0/state 2>/dev/null; then
      sleep 0.5
      if [ -e /sys/bus/serio/drivers/atkbd/serio0 ]; then
        echo -n "serio0" > /sys/bus/serio/drivers/atkbd/unbind 2>/dev/null || true
        sleep 0.2
        echo -n "serio0" > /sys/bus/serio/drivers/atkbd/bind 2>/dev/null || true
      fi
      if [ -e /sys/bus/i2c/drivers/i2c_hid_acpi/i2c-ELAN06FA:00 ]; then
        echo "i2c-ELAN06FA:00" > /sys/bus/i2c/drivers/i2c_hid_acpi/unbind 2>/dev/null || true
        sleep 0.2
        echo "i2c-ELAN06FA:00" > /sys/bus/i2c/drivers/i2c_hid_acpi/bind 2>/dev/null || true
      fi
    else
      sleep 5
    fi
    ;;
esac
