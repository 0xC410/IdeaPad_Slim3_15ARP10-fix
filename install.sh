#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Lenovo IdeaPad Slim 3 15ARP10 (83MM) - Linux Fix Installer
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="${SCRIPT_DIR}/files"

SKIP_DKMS=0
SKIP_CINNAMON=0

for arg in "$@"; do
  case "$arg" in
    --skip-dkms) SKIP_DKMS=1 ;;
    --skip-cinnamon) SKIP_CINNAMON=1 ;;
    -h|--help)
      echo "Usage: sudo ./install.sh [--skip-dkms] [--skip-cinnamon]"
      echo "  --skip-dkms      Skip installing the DanielGibson/amd_pmc-ideapad DKMS module"
      echo "  --skip-cinnamon  Skip updating Cinnamon power management settings"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      exit 1
      ;;
  esac
done

if [ "${EUID}" -ne 0 ]; then
  echo "[ERROR] Please run this script as root: sudo ./install.sh"
  exit 1
fi

log() {
  echo "[+] $*"
}

warn() {
  echo "[!] $*"
}

# ------------------------------------------------------------------------------
# 1. amd_pmc DKMS module (delay_suspend workaround for Kernel Bugzilla #221383)
# ------------------------------------------------------------------------------
if [ "${SKIP_DKMS}" -eq 0 ]; then
  if modinfo amd_pmc 2>/dev/null | grep -q "parm:.*delay_suspend"; then
    log "amd_pmc already supports delay_suspend (DKMS or mainline kernel). Skipping DKMS build."
  else
    log "Current amd_pmc lacks delay_suspend. Installing DanielGibson/amd_pmc-ideapad via DKMS..."
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -qq
      apt-get install -y git dkms build-essential "linux-headers-$(uname -r)"
    else
      warn "apt-get not found. Make sure git, dkms, build tools, and kernel headers are installed."
    fi

    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "${TMP_DIR}"' EXIT
    git clone --depth 1 https://github.com/DanielGibson/amd_pmc-ideapad.git "${TMP_DIR}/amd_pmc-ideapad"

    if [ -f "${TMP_DIR}/amd_pmc-ideapad/dkms.conf" ]; then
      PKG_VER="$(grep -E '^PACKAGE_VERSION=' "${TMP_DIR}/amd_pmc-ideapad/dkms.conf" | cut -d'"' -f2)"
      PKG_VER="${PKG_VER:-0.0.4}"
      DEST_SRC="/usr/src/amd_pmc-${PKG_VER}"
      rm -rf "${DEST_SRC}"
      cp -r "${TMP_DIR}/amd_pmc-ideapad" "${DEST_SRC}"
      dkms add -m amd_pmc -v "${PKG_VER}" || true
      dkms build -m amd_pmc -v "${PKG_VER}"
      dkms install -m amd_pmc -v "${PKG_VER}" --force
      log "DKMS module amd_pmc/${PKG_VER} installed successfully."
    else
      warn "dkms.conf not found in cloned repository. Please install amd_pmc-ideapad manually."
    fi
  fi
else
  log "Skipping DKMS installation (--skip-dkms)."
fi

# ------------------------------------------------------------------------------
# 2. Kernel module options (modprobe.d)
# ------------------------------------------------------------------------------
log "Installing /etc/modprobe.d/amd_pmc.conf and /etc/modprobe.d/rtw89.conf..."
install -m 0644 "${FILES_DIR}/amd_pmc.conf" /etc/modprobe.d/amd_pmc.conf
install -m 0644 "${FILES_DIR}/rtw89.conf" /etc/modprobe.d/rtw89.conf

# ------------------------------------------------------------------------------
# 3. systemd hooks (sleep and shutdown)
# ------------------------------------------------------------------------------
log "Installing sleep hook to /lib/systemd/system-sleep/fix-ideapad-input.sh..."
mkdir -p /lib/systemd/system-sleep
install -m 0755 "${FILES_DIR}/fix-ideapad-input.sh" /lib/systemd/system-sleep/fix-ideapad-input.sh

log "Installing shutdown hook to /lib/systemd/system-shutdown/fix-ideapad-poweroff.sh..."
mkdir -p /lib/systemd/system-shutdown
install -m 0755 "${FILES_DIR}/fix-ideapad-poweroff.sh" /lib/systemd/system-shutdown/fix-ideapad-poweroff.sh

log "Configuring DefaultTimeoutStopSec=10s in /etc/systemd/system.conf.d/50-ideapad-shutdown.conf..."
mkdir -p /etc/systemd/system.conf.d
install -m 0644 "${FILES_DIR}/50-ideapad-shutdown.conf" /etc/systemd/system.conf.d/50-ideapad-shutdown.conf

# ------------------------------------------------------------------------------
# 4. GRUB kernel parameters (acpi=force amdgpu.dcdebugmask=0x10)
# ------------------------------------------------------------------------------
GRUB_FILE="/etc/default/grub"
if [ -f "${GRUB_FILE}" ]; then
  BACKUP_FILE="${GRUB_FILE}.ideapad-fix.bak.$(date +%Y%m%d%H%M%S)"
  cp "${GRUB_FILE}" "${BACKUP_FILE}"
  log "Saved GRUB backup to ${BACKUP_FILE}"

  CURRENT_CMDLINE="$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "${GRUB_FILE}" | sed -E 's/^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"/\1/')"
  NEW_CMDLINE="${CURRENT_CMDLINE}"

  for param in "acpi=force" "amdgpu.dcdebugmask=0x10"; do
    case " ${NEW_CMDLINE} " in
      *" ${param} "*) ;;
      *) NEW_CMDLINE="${NEW_CMDLINE} ${param}" ;;
    esac
  done

  # Trim redundant whitespace
  NEW_CMDLINE="$(echo "${NEW_CMDLINE}" | xargs)"

  sed -i -E "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${NEW_CMDLINE}\"|" "${GRUB_FILE}"
  log "Updated GRUB_CMDLINE_LINUX_DEFAULT to: \"${NEW_CMDLINE}\""

  if command -v update-grub >/dev/null 2>&1; then
    update-grub
  elif command -v grub-mkconfig >/dev/null 2>&1; then
    grub-mkconfig -o /boot/grub/grub.cfg
  else
    warn "Neither update-grub nor grub-mkconfig found. Please update your bootloader manually."
  fi
else
  warn "${GRUB_FILE} not found. Manually add 'acpi=force amdgpu.dcdebugmask=0x10' to your bootloader config."
fi

# ------------------------------------------------------------------------------
# 5. Cinnamon power management (disable inactivity auto-suspend)
# ------------------------------------------------------------------------------
if [ "${SKIP_CINNAMON}" -eq 0 ] && command -v gsettings >/dev/null 2>&1; then
  TARGET_USER="${SUDO_USER:-}"
  if [ -n "${TARGET_USER}" ] && [ "${TARGET_USER}" != "root" ]; then
    TARGET_UID="$(id -u "${TARGET_USER}")"
    if [ -S "/run/user/${TARGET_UID}/bus" ]; then
      log "Disabling Cinnamon inactivity auto-suspend for user '${TARGET_USER}'..."
      sudo -u "${TARGET_USER}" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus" \
        gsettings set org.cinnamon.settings-daemon.plugins.power sleep-inactive-ac-timeout 0 || true
      sudo -u "${TARGET_USER}" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${TARGET_UID}/bus" \
        gsettings set org.cinnamon.settings-daemon.plugins.power sleep-inactive-battery-timeout 0 || true
    else
      warn "User D-Bus session not found for '${TARGET_USER}'. Run manually without sudo:"
      echo "    gsettings set org.cinnamon.settings-daemon.plugins.power sleep-inactive-ac-timeout 0"
      echo "    gsettings set org.cinnamon.settings-daemon.plugins.power sleep-inactive-battery-timeout 0"
    fi
  fi
fi

echo ""
echo "=============================================================================="
echo " Installation complete! Reboot your laptop to apply all changes:"
echo "   sudo reboot"
echo "=============================================================================="
