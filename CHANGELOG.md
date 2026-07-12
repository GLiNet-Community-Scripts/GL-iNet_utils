# Changelog

All notable changes to the GL.iNet Utilities toolkit. Newest first. Versions
match the `# Version:` line in the script — `YYYY-MM-DD`, or `YYYY-MM-DD_HH:MM`
for multiple releases on the same day.

## 2026-07-12
- Hardware Info reports Wi-Fi MIMO from the driver's configured antenna
  chainmask (correct 2x2 / 3x3 / 4x4 per band) instead of inferring it from the
  channel width, which mislabeled radios that run more than two spatial streams.

## 2026-07-10
- Change Log & Updates are now one screen: browse the full history in the house
  pager and update in place with `[U]` — the separate "Check for Updates" item
  is gone.
- Toolkit Management STATUS now shows your running version and whether an update
  is available.
- The changelog viewer marks where your installed version sits, so everything
  above the line is what's new to you.

## 2026-07-09
- Benchmark leaderboards expanded — added Flint 2, Beryl AX, Brume 3, Flint 3,
  and Beryl (original) as reference devices.
- VPN & Crypto benchmark now paginates by test (WireGuard / OpenVPN / RSA on
  their own pages), so it stays readable as the device list grows.
- Memory benchmark runs much faster on low-RAM devices (smaller test size).
- Terminal auto-sizing and a dark theme on launch, restored when you exit.
- More reliable terminal detection: it requires a real `stty` and, when it
  can't probe, falls back to clean Compatible mode instead of a mixed profile.
- Display Settings now shows your saved default, and your preference survives
  script updates.
- New: see what's changed before updating, plus a "Display Change Log" option
  under Toolkit Management.

## 2026-07-04
- Cross-device benchmark leaderboards (VPN & Crypto, Disk, Memory), ranked
  against saved reference routers instead of a single baseline.
- Renders correctly in PuTTY and Windows Terminal, not just macOS/iTerm
  (adaptive symbol set that avoids garbled boxes and misaligned columns).
- Robust CPU frequency detection (lscpu / cpufreq sysfs / device-tree OPP).
- Install as a system command (Toolkit Management) with sysupgrade persistence.
- UI/UX standardization pass across menus: input prompts, alignment, dividers,
  and spacing.
- Restore only offers components that were actually backed up.

## 2026-04-19
- Clearer wording in the zram swap tuning help.

## 2026-04-16
- Web terminal (ttyd) now supports HTTPS.

## 2026-04-10
- New: browser-based web terminal (ttyd) launched straight from the router.

## 2026-03-21
- New: guest-network controls — set per-guest speed limits and optionally allow
  the guest network to reach the router.

## 2026-03-15
- Refined fan-speed calculation.

## 2026-03-13
- Fan control now shows a live, real-time readout.
- New: iperf network performance testing.

## 2026-03-12
- Faster Hardware Information screen with UI polish.
- Better hardware detection on older routers.
- Fixed a rounding error in manual fan control.

## 2026-03-11
- New: System Tweaks menu — fan control, package manager, and SSH-key install.
- Fixed the Apache benchmark package dependency (apache-utils → apache).

## 2026-03-05
- New: install a LibreSpeed test server.

## 2026-03-02
- New: Ookla Speedtest Server benchmark.
- Stress test display supports a wider range of devices and temperatures.

## 2026-03-01
- More reliable CPU info (lscpu) and disk-space reporting when AdGuardHome was
  never installed.
- Unified benchmark UI.

## 2026-02-28
- New: real-time monitoring of CPU fan, temperature, and uptime.
- Falls back to stress-ng where stress isn't available on OpenWrt.

## 2026-02-22
- Menu option updates.

## 2026-02-21
- Fixed memory and storage calculation on the Beryl (original).

## 2026-02-20
- New: OpenSpeedTest server installer — the toolkit is now all-in-one.
- AdGuardHome handles client requests.
- Assorted UI fixes.

## 2026-02-19
- Fixed disk-size detection.
- Benchmark UI formatting fixes, including the Memory I/O test.

## 2026-02-15
- Major reorganization of the toolkit.
- New: SOS AdGuardHome factory restore.
- Expanded benchmark suite and added LAN info.
- More precise DNS benchmark.

## 2026-02-11
- New: manage AdGuardHome direct access.
- New: clean up old backups.
- Unified GUI elements.

## 2026-02-10
- Wireless detection now reports interface, band, HT mode, MIMO, and channel for
  each radio.
- AdGuardHome maintenance grouped under an "AdGuardHome Maintenance Hub."

## 2026-02-08
- First public release.
- AdGuardHome Lists Manager, wireless interface detection, and refined menus,
  help text, and install/removal flows.

## 2026-02-07
- Initial toolkit script.
