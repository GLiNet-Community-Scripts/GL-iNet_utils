# GL.iNet Utilities Script for OpenWrt Routers

```
   _____ _          _ _    _      _   
  / ____| |        (_) \\ | |    | |  
 | |  __| |  ______ _|  \\| | ___| |_ 
 | | |_ | | |______| | . \` |/ _ \\ __|
 | |__| | |____    | | |\\  |  __/ |_ 
 \\_____|______|   |_|_| \\_|\\___|\\__|

         GL.iNet Utilities Toolkit

```

> 🛠️ A growing collection of practical utilities for managing and tuning GL.iNet routers via a single interactive script.

---

## Features

- 🖥️ **Deep Hardware Insights**
  - **Real-time Monitoring:** Total visibility into CPU load/frequency, a full RAM breakdown (free/used/available/cache), storage, uptime, temperatures, and fan speeds — with one-key masking of MAC/serial/device IDs for safe screen-sharing.
  - **Network Topology:** Paged navigation for network interfaces and wireless radio details (Link speeds, MIMO, Channel bandwidth).
  - **VPN Crypto Audit:** Instantly verify if your hardware acceleration (AES-CE, NEON) is active at the kernel level for optimized OpenVPN and WireGuard performance.
- 🛠️ **AdGuardHome Control Center**
  - **Service Management:** A central hub to toggle AGH, manage UI updates, and bulk-import pre-set blocklists/allowlists.
  - **Industrial Self-Healing:** Fail-safe logic that pulls pristine binaries or init scripts from /rom if your current installation becomes corrupted.
  - **Surgical Backups:** Precision tracking of configurations, binaries, and scripts with automated timestamping and integrity checks that persist through firmware upgrades.
- ⚙️ **System Tweaks**
  - **Zram Tuning:** Essential for low-RAM devices (e.g., Beryl 7/MT3600BE). Easily install and tune compressed RAM swap to reduce OOM (Out-of-Memory) crashes.
  - **Guest Network Limiter:** Global speed control for the entire guest subnet and the ability to toggle guest access to the router’s local IP.
  - **Advanced Fan Control:** Granular management of Min/Max thresholds, "Fan-on" triggers, and thermal warnings with direct UI integration.
  - **Web-UI Terminal:** Embeds a fully functional Linux terminal directly into the GL.iNet Admin Panel. Adds a `>_` icon to the navigation bar that opens a draggable, resizable, minimizable terminal modal powered by ttyd. Supports both HTTP and HTTPS modes.
  - **DevOps Tools:** Automated SSH Key installer and a Package Manager to persist essential CLI tools across sysupgrades.
  - **Toolkit Management:** Install the toolkit as a system command — copies it to `/usr/sbin/glinet_utils` so you can launch it from any directory by just typing `glinet_utils`, with optional `sysupgrade.conf` persistence so it (and its self-updates) survive firmware upgrades.
- 📊 **Performance Benchmarks**
  - **Cross-Device Leaderboards:** A VPN & Crypto benchmark (WireGuard/ChaCha20, OpenVPN/AES-GCM, and RSA handshake), plus CPU thermal stress and raw Disk/Memory I/O — each ranked against saved reference routers instead of a single baseline — alongside DNS latency.
  - **Network Probing:** Integrated support for Ookla Speedtest, LibreSpeed, and OpenSpeedTest server environments.
- 🔐 **VPN Tools**
  - **MTU Optimizer:** Finds your active WireGuard and OpenVPN tunnels — client or server — and recommends the right MTU (the underlay link MTU minus that protocol's exact overhead), so tunnelled traffic stops fragmenting and silently losing throughput. Apply it with one keypress, set a value by hand, run an optional active probe, or reset to the router's default. On routers with more than one tunnel, Optimize and Reset can act on all of them at once, each with its own correct value.
  - **Written where the router expects it:** the MTU goes into GL.iNet's own VPN configuration rather than a generic network setting, so it appears in the Admin Panel under that tunnel's Options and survives a reboot. On older firmware, where the web UI can set an MTU but not clear it again, Reset is the only way back to the default.
- 📋 **Secure UCI Viewer:** Quick, read-only access to your system config. Audit SSIDs, Wi-Fi keys, VPN tunnels, and GoodCloud settings without digging through the CLI.
- 🔄 **Native Self-Updater:** Stay current with zero effort. The script checks GitHub on launch and can perform an in-place update.
- 🆓 **GPL-3.0 Licensed:** Free, open, and community-driven.

Tested on various GL.iNet models (Beryl, Beryl AX, Beryl 7, Slate 7, Flint 3, Flint 3e, etc.) running recent firmware.

---

## 🚀 Installation

1. SSH into your GL.iNet router:

```
ssh root@192.168.8.1
```

2. Download the script:

```
wget -O glinet_utils.sh https://raw.githubusercontent.com/phantasm22/GL-iNet_utils/main/glinet_utils.sh && chmod +x glinet_utils.sh
```

3. Run the script:

```
./glinet_utils.sh
```

> 💡 Once it's running, open **System Tweaks → Toolkit Management** to install it as a system command — it copies to `/usr/sbin/glinet_utils` so you can launch it from any directory by just typing `glinet_utils`, and can persist across firmware upgrades.

---

## 📸 Screenshots / Usage

When launched, the script presents an interactive menu system.  
Options may vary as new utilities are added, but generally include:

Main Menu

```
1️⃣  Show Hardware Information
2️⃣  AdGuardHome Control Center
3️⃣  System Tweaks
4️⃣  System Benchmarks
5️⃣  VPN Tools
6️⃣  View System Configuration (UCI)
0️⃣  Exit
❓ Help


```

AdGuardHome Control Center

```
1️⃣  Start AdGuardHome            (Restart / Stop when already running)
2️⃣  Manage Allow/Blocklists
3️⃣  Setup, Access & UI Updates
4️⃣  Backup & Recovery Suite
5️⃣  Logs & Maintenance
🆑 Reset to Factory Settings (Start Over)
0️⃣  Main menu
❓ Help
```

System Tweaks

```
1️⃣  Device Fan Settings
2️⃣  Manage Zram Swap
3️⃣  Guest Network Bandwidth Limiter
4️⃣  Web-UI Terminal Interface
5️⃣  Package and Persistence Manager
6️⃣  SSH Key Management
7️⃣  Toolkit Management
0️⃣  Main menu
❓ Help
```

System Benchmarks

```
1️⃣  CPU Thermal Stress Test
2️⃣  VPN & Crypto Benchmark
3️⃣  Disk I/O Benchmark
4️⃣  Memory I/O Benchmark
5️⃣  DNS Latency Benchmark
6️⃣  Ookla Internet Speedtest
7️⃣  LibreSpeed Speed Test Server
8️⃣  iPerf3 Network Speed Test Server
9️⃣  OpenSpeedTest Server
0️⃣  Main menu
❓ Help


```

VPN Tools

```
1️⃣  VPN MTU Optimizer
0️⃣  Main menu
```

VPN MTU Optimizer

```
WireGuard Server: wgserver
   Current MTU:  1391   (override)
   Underlay:     eth2 (MTU 1500)
   Overhead:     -60 (WireGuard / IPv4)
   Recommended:  1440   (can raise)

1️⃣  Optimize a tunnel (apply recommended)
2️⃣  Set MTU manually
3️⃣  Verify with an active probe
4️⃣  Reset MTU (remove override)
0️⃣  Back
```

System Configuration Viewer

```
1️⃣  Wireless Networks
2️⃣  Network Configuration
3️⃣  VPN Configuration
4️⃣  System Settings
5️⃣  Cloud Services
0️⃣  Main menu
❓ Help
```



Most sections include built-in help text and confirmation prompts for safety.

---


## 🔧 Requirements

- GL.iNet router running OpenWrt-based firmware (most models supported)
- SSH access (root login enabled)
- Internet connection for updates, package installs & benchmarks
- Optional: `opkg` packages (lscpu, stress, etc.) are installed automatically when needed
  
---

## ⚙️ Updating the Script

The toolkit includes a built-in update checker (automatic on start, or via System Tweaks → Toolkit Management).

To force an update manually:

```bash
wget -O glinet_utils.sh https://raw.githubusercontent.com/phantasm22/GL-iNet_utils/main/glinet_utils.sh
chmod +x glinet_utils.sh
./glinet_utils.sh
```

---

## 🗑️ Uninstall / Cleanup

Simply delete the script file:

```bash
rm glinet_utils.sh
```

If you used features that install additional components, remove them manually as desired:

```bash
# Web-UI Terminal
opkg remove ttyd
rm -f /etc/config/ttyd /etc/ttyd.crt /etc/ttyd.key

# Zram / stress tools
opkg remove zram-swap stress

# System-command install (or remove it via System Tweaks → Toolkit Management)
rm -f /usr/sbin/glinet_utils
sed -i '\|/usr/sbin/glinet_utils|d' /etc/sysupgrade.conf
```

---

## ❤️ Credits & Author

Created by **phantasm22**  
https://github.com/phantasm22  

Inspired by the need for a simple, powerful toolkit tailored for GL.iNet routers. 
If you have a utility you run on every GL.iNet router you touch, it probably belongs here.

Contributions, bug reports & feature suggestions welcome!

Star ⭐ the repo if you find it useful!


---

## 📜 License

This project is licensed under the **GNU GPL v3.0 License**.  
See the [LICENSE](https://www.gnu.org/licenses/gpl-3.0.en.html) file for details.
