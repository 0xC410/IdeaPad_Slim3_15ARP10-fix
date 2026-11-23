#!/bin/sh
# Lenovo IdeaPad Slim 3 15ARP10 (83MM) - systemd sleep hook
# 1. pre:
#    - Disables wakeup on internal keyboard (IRQ 1), ELAN touchpad (GPIO 9), and Wi-Fi PCIe root port (GPP6).
#    - Cleanly unloads Realtek RTL8852BE Wi-Fi (rtw89) and Bluetooth (btusb) drivers so they cannot hang s2idle
#      or trigger PCIe/D3cold/IOMMU conflicts on suspend entry.
# 2. post:
#    - If the lid is open, waits 0.5s for the EC to settle, reloads rtw89_8852be & btusb, and rebinds
#      atkbd (serio0) and i2c_hid_acpi (ELAN06FA:00).
#    - If the system woke while the lid is still closed (spurious wake / AC plug), keeps Wi-Fi/BT unloaded,
#      skips input rebind, and sleeps 5s to prevent an instant re-suspend lockup.

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

    # Unload Realtek Wi-Fi & Bluetooth stack before s2idle
    modprobe -r rtw89_8852be rtw89_8852b rtw89_8852b_common rtw89_pci rtw89_core 2>/dev/null || true
    modprobe -r btusb 2>/dev/null || true
    ;;

  post)
    if grep -q "open" /proc/acpi/button/lid/LID0/state 2>/dev/null; then
      sleep 0.5

      # Reload Realtek Wi-Fi & Bluetooth stack
      modprobe rtw89_8852be 2>/dev/null || true
      modprobe btusb 2>/dev/null || true

      # Rebind internal keyboard (atkbd) and I2C touchpad (ELAN06FA:00)
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
