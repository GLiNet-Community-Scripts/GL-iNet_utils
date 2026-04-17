# GL.iNet Utilities Script for OpenWrt Routers

```
   _____ _          _ _   _      _   
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
  - **Real-time Monitoring:** Total visibility into CPU load, RAM utilization, storage, uptime, temperatures, and fan speeds.
  - **Network Topology:** Paged navigation for network interfaces and wireless radio details (Link speeds, MIMO, Channel bandwidth).
  - **VPN Crypto Audit:** Instantly verify if your hardware acceleration (AES-CE, NEON) is active at the kernel level for optimized OpenVPN and WireGuard performance.
- 🛠️ **AdGuardHome Control Center**
  - **Service Management:** A central hub to toggle AGH, manage UI updates, and bulk-import pre-set blocklists/allowlists.
  - **Industrial Self-Healing:** Fail-safe logic that pulls pristine binaries or init scripts from /rom if your current installation becomes corrupted.
  - **Surgical Backups:** Precision tracking of configurations, binaries, and scripts with automated timestamping and integrity checks that persist through firmware upgrades.
- ⚙️ **System Tweaks**
  - **Zram Tuning:** Essential for low-RAM devices (e.g., Beryl G7/MT3000). Easily install and tune compressed RAM swap to prevent OOM (Out-of-Memory) crashes.
  - **Guest Network Limiter:** Global speed control for the entire guest subnet and the ability to toggle guest access to the router’s local IP.
  - **Advanced Fan Control:** Granular management of Min/Max thresholds, "Fan-on" triggers, and thermal warnings with direct UI integration.
  - **Web-UI Terminal:** Embeds a fully functional Linux terminal directly into the GL.iNet Admin Panel. Adds a `>_` icon to the navigation bar that opens a draggable, resizable, minimizable terminal modal powered by ttyd. Supports both HTTP and HTTPS modes.
  - **DevOps Tools:** Automated SSH Key installer and a Package Manager to persist essential CLI tools across sysupgrades.
- 📊 **Performance Benchmarks**
  - **Hardware Stress Testing:** Real-world testing of CPU cycles, OpenSSL throughput, raw Disk/Memory I/O, and DNS latency compared to a Beryl G7 baseline.
  - **Network Probing:** Integrated support for Ookla Speedtest, LibreSpeed, and OpenSpeedTest server environments.
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
5️⃣  View System Configuration (UCI)
6️⃣  Check for Update
0️⃣  Exit


```

AdGuardHome Control Center

```
1️⃣  Manage Allow/Blocklists
2️⃣  Setup, Access & UI Updates
3️⃣  Backup & Recovery Suite
4️⃣  Service, Logs & Cache Purge
🆑 Reset to Factory Settings (Start Over)
0️⃣  Back to Main Menu
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
0️⃣  Main menu
❓ Help
```

System Benchmarks

```
1️⃣  CPU Thermal Stress Test
2️⃣  CPU Benchmark (OpenSSL)
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

System Configuration Viewer

```
1️⃣  Wireless Networks
2️⃣  Network Configuration
3️⃣  VPN Configuration
4️⃣  System Settings
5️⃣  Cloud Services
0️⃣  Main menu
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

The toolkit includes a built-in update checker (option 6 or automatic on start).

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
