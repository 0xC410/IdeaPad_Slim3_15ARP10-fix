#!/bin/sh
# Lenovo IdeaPad Slim 3 15ARP10 (83MM) - systemd shutdown hook
# Disables USB/xHCI controller wakeups on poweroff so the Embedded Controller cleanly cuts power (ACPI S5).

if [ "$1" = "poweroff" ]; then
  for dev in XHC0 XHC1 XHC2 XHC3 XHC4; do
    if grep -q "${dev}.*\*enabled" /proc/acpi/wakeup 2>/dev/null; then
      echo "$dev" > /proc/acpi/wakeup 2>/dev/null || true
    fi
  done
fi
