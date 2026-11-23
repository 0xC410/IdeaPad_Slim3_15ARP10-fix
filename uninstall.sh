#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Lenovo IdeaPad Slim 3 15ARP10 (83MM) - Uninstaller
# ==============================================================================

if [ "${EUID}" -ne 0 ]; then
  echo "[ERROR] Please run this script as root: sudo ./uninstall.sh"
  exit 1
fi

log() {
  echo "[-] $*"
}

log "Removing modprobe configurations and udev rules..."
rm -f /etc/modprobe.d/amd_pmc.conf
rm -f /etc/modprobe.d/rtw89.conf
rm -f /etc/udev/rules.d/99-rtw89-suspend.rules
if command -v udevadm >/dev/null 2>&1; then
  udevadm control --reload-rules || true
fi

log "Removing systemd hooks and overrides..."
rm -f /lib/systemd/system-sleep/fix-ideapad-input.sh
rm -f /lib/systemd/system-shutdown/fix-ideapad-poweroff.sh
rm -f /etc/systemd/system.conf.d/50-ideapad-shutdown.conf

echo ""
echo "[!] Note: If you also want to remove the amd_pmc DKMS module, run:"
echo "    sudo dkms remove -m amd_pmc -v <VERSION> --all"
echo "    (check the installed version with: dkms status)"
echo ""
echo "Reboot your laptop to complete removal: sudo reboot"
