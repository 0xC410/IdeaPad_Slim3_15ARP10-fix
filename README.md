# IdeaPad_Slim3_15ARP10-fix

Automated Linux fixes for **suspend (`s2idle`)**, **internal keyboard/touchpad input**, and **incomplete shutdown (`ACPI S5`)** issues on the **Lenovo IdeaPad Slim 3 15ARP10** (tested on Linux Mint / Ubuntu 24.04 with Cinnamon and kernel `7.0.0-34-generic`).

## Target Hardware

| Component | Details |
|---|---|
| **Model / DMI** | Lenovo IdeaPad Slim 3 15ARP10 (`83MM` / board `LNVNB161216`) |
| **Tested BIOS** | `QBCN26WW` (`09/23/2025`) |
| **CPU / GPU** | AMD Ryzen 7 7735HS (Rembrandt / Zen 3+) + Radeon 680M (`amdgpu`) |
| **Internal Keyboard** | `AT Translated Set 2 keyboard` (`i8042` / `PNP0303:KBC0` / `serio0` / IRQ 1) |
| **Touchpad** | `ELAN06FA:00 04F3:327E` (`i2c_hid_acpi` / `AMDI0010:01` / `amd_gpio` pin 9) |
| **Wi-Fi / Bluetooth** | Realtek `rtw89_8852be` + Realtek Bluetooth (`hci0`) |
| **Sleep Mode** | `s2idle` only (Modern Standby / S0ix) |

---

## Root Causes & Fixes

### 1. Dead internal keyboard after closing and reopening the lid (`s2idle`)
- **Root Cause:** A known Embedded Controller (EC) firmware timing bug on AMD Zen 3 / Zen 3+ Lenovo IdeaPad laptops ([Kernel Bugzilla #221383](https://bugzilla.kernel.org/show_bug.cgi?id=221383)). Linux transitions into `s2idle` too quickly before the EC finishes its internal housekeeping, causing the EC to stop sending keyboard (`i8042`) and lid-switch (`LID0`) events upon resume.
- **Fix:**
  - Installs the patched `amd_pmc` DKMS module ([DanielGibson/amd_pmc-ideapad](https://github.com/DanielGibson/amd_pmc-ideapad)) that adds a 2.5-second pre-suspend delay (`delay_suspend`), unless the running kernel already supports `delay_suspend` natively (merged upstream in kernels `6.12.100+`, `6.18.41+`, `7.1.5+`, and `7.2+`).
  - Installs `/etc/modprobe.d/amd_pmc.conf` with:
    ```ini
    options amd_pmc delay_suspend=1
    ```
- **Known Pitfalls (What NOT to do):**
  - **Do NOT set `enable_stb=1` on `amd_pmc`**: on this Ryzen 7 7735HS platform, `amd_stb_s2d_init()` returns `-EIO` (`probe with driver amd_pmc failed with error -5`), preventing `amd_pmc` from binding at all and breaking the 2.5s delay.
  - **Do NOT add `i8042.nopnp`, `i8042.reset`, `i8042.nomux`, or `i8042.noloop` to GRUB**: these break ACPI/PNP registration of `PNP0303:KBC0` expected by the Lenovo EC.

---

### 2. Spurious wakeups while lid is closed, instant re-suspend lockups, and unresponsive input on resume
- **Root Cause:**
  1. While the lid is closed, the internal keyboard (`serio0` / IRQ 1), the capacitive touchpad (`i2c-ELAN06FA:00` / GPIO 9, resting directly against the closed screen), and the Wi-Fi PCIe root port (`GPP6`) remain enabled as wakeup sources, causing spurious wakeups seconds after closing the lid.
  2. When a spurious wakeup occurs with the lid still closed, `systemd-logind` detects the closed lid and triggers another suspend within ~100ms, colliding with input/Bluetooth driver re-initialization and locking up the EC/SoC.
  3. On certain `s2idle` resumes, `atkbd` (`serio0`) or `i2c_hid_acpi` (`i2c-ELAN06FA:00`) must be rebound after the EC settles.
- **Fix (`files/fix-ideapad-input.sh` -> `/lib/systemd/system-sleep/fix-ideapad-input.sh`):**
  - **`pre` phase (before suspend):** disables wakeup on `serio0`, `i2c-ELAN06FA:00`, and `GPP6` (leaving the lid switch `LID0` and power button enabled).
  - **`post` phase (after resume):**
    - Checks `/proc/acpi/button/lid/LID0/state`.
    - If the lid is **`open`**: waits `0.5s` and cleanly unbinds/rebinds `atkbd/serio0` and `i2c_hid_acpi/i2c-ELAN06FA:00`.
    - If the lid is still **`closed`** (e.g., AC charger plugged/unplugged): skips input rebinding and sleeps `5s` so hardware and kernel queues settle before `systemd-logind` re-suspends.

---

### 3. Inactivity auto-suspend (lid open) losing keyboard and touchpad input
- **Root Cause:** When the laptop enters `s2idle` due to inactivity while the lid remains open, there is no physical lid-open transition (`LID0`) on resume, and the EC often fails to re-enable internal keyboard/touchpad scanning or wakeups.
- **Fix:**
  - Disables inactivity auto-suspend in Cinnamon (`sleep-inactive-ac-timeout=0` and `sleep-inactive-battery-timeout=0`) while preserving display sleep (`sleep-display`) and lid-close suspend (`lid-close`).

---

### 4. Incomplete shutdown (screen turns off, but power LED stays on and battery drains)
- **Root Cause:** `systemd` stops all services and unmounts filesystems cleanly within ~3 seconds (`Journal stopped`), so data is safe, but the kernel hangs inside `kernel_power_off()` before completing the **ACPI S5** power-cut handoff to the motherboard. Logs on this hardware point to three contributing factors:
  1. **AMD GPU (`amdgpu` DCN 3.1):** `[drm] REG_WAIT timeout 1us * 100 tries - dcn31_program_compbuf_size` during display teardown.
  2. **Realtek Wi-Fi (`rtw89_8852be`):** `timed out to flush queues` and `AMD-Vi: IO_PAGE_FAULT` caused by PCIe ASPM L1.
  3. **USB/xHCI controllers (`XHC0`–`XHC4`):** active ACPI wakeups during `poweroff` can prevent the EC from dropping power rails.
- **Fix:**
  - Appends `acpi=force amdgpu.dcdebugmask=0x10` to `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`.
  - Installs `/etc/modprobe.d/rtw89.conf` with `options rtw89_pci disable_aspm_l1=y disable_aspm_l1ss=y`.
  - Installs `/lib/systemd/system-shutdown/fix-ideapad-poweroff.sh` to disable `XHC0`–`XHC4` wakeups in `/proc/acpi/wakeup` on `poweroff`.
  - Sets `DefaultTimeoutStopSec=10s` in `/etc/systemd/system.conf.d/50-ideapad-shutdown.conf`.

---

## Usage

### Install
```bash
git clone https://github.com/<your-username>/IdeaPad_Slim3_15ARP10-fix.git
cd IdeaPad_Slim3_15ARP10-fix
chmod +x install.sh uninstall.sh
sudo ./install.sh
sudo reboot
```

Optional installer flags:
- `sudo ./install.sh --skip-dkms` — skip installing the `amd_pmc` DKMS module (useful on kernels `7.1.5+` / `7.2+` that include the upstream fix).
- `sudo ./install.sh --skip-cinnamon` — skip Cinnamon `gsettings` power changes (useful on other desktop environments).

### Post-Reboot Verification
```bash
# 1. Verify active GRUB kernel parameters
cat /proc/cmdline

# 2. Verify amd_pmc loaded cleanly (no "error -5") and delay_suspend is active
dmesg | grep -i amd_pmc
cat /sys/module/amd_pmc/parameters/delay_suspend   # expected: 1

# 3. Verify Realtek rtw89 ASPM L1 workaround
cat /sys/module/rtw89_pci/parameters/disable_aspm_l1  # expected: Y
```

### Uninstall
```bash
sudo ./uninstall.sh
sudo reboot
```
