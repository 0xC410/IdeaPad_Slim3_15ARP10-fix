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

log "Removing modprobe configurations..."
rm -f /etc/modprobe.d/amd_pmc.conf
rm -f /etc/modprobe.d/rtw89.conf

log "Removing systemd hooks and overrides..."
rm -f /lib/systemd/system-sleep/fix-ideapad-input.sh
rm -f /lib/systemd/system-shutdown/fix-ideapad-poweroff.sh
rm -f /etc/systemd/system.conf.d/50-ideapad-shutdown.conf

GRUB_FILE="/etc/default/grub"
if [ -f "${GRUB_FILE}" ]; then
  log "Removing 'acpi=force' and 'amdgpu.dcdebugmask=0x10' from GRUB..."
  CURRENT_CMDLINE="$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "${GRUB_FILE}" | sed -E 's/^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"/\1/')"
  NEW_CMDLINE="$(echo "${CURRENT_CMDLINE}" | sed -E 's/\bacpi=force\b//g; s/\bamdgpu\.dcdebugmask=0x10\b//g' | xargs)"
  sed -i -E "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${NEW_CMDLINE}\"|" "${GRUB_FILE}"

  if command -v update-grub >/dev/null 2>&1; then
    update-grub
  elif command -v grub-mkconfig >/dev/null 2>&1; then
    grub-mkconfig -o /boot/grub/grub.cfg
  fi
fi

echo ""
echo "[!] Note: If you also want to remove the amd_pmc DKMS module, run:"
echo "    sudo dkms remove -m amd_pmc -v <VERSION> --all"
echo "    (check the installed version with: dkms status)"
echo ""
echo "Reboot your laptop to complete removal: sudo reboot"
