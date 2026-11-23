#!/bin/sh
# Lenovo IdeaPad Slim 3 15ARP10 (83MM) - systemd shutdown hook
# Runs on poweroff, reboot, and halt:
# 1. Cleanly unloads Realtek RTL8852BE Wi-Fi (rtw89) and Bluetooth (btusb) drivers before kernel PCIe teardown
#    to prevent post-journald hangs leaving the power LED on.
# 2. Disables USB/xHCI and Wi-Fi PCIe ACPI wakeups so the Embedded Controller cleanly cuts power (ACPI S5) or resets.

case "$1" in
  poweroff|reboot|halt)
    modprobe -r rtw89_8852be rtw89_8852b rtw89_8852b_common rtw89_pci rtw89_core 2>/dev/null || true
    modprobe -r btusb 2>/dev/null || true

    for dev in GPP6 XHC0 XHC1 XHC2 XHC3 XHC4; do
      if grep -q "${dev}.*\*enabled" /proc/acpi/wakeup 2>/dev/null; then
        echo "$dev" > /proc/acpi/wakeup 2>/dev/null || true
      fi
    done
    ;;
esac
