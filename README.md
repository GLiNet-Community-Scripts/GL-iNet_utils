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

- 🚀 Key Features
- 🖥️ Deep Hardware Insights – Total visibility into your CPU, RAM, and storage. Includes paged navigation for network interfaces and wireless radio details.
- 🛡️ VPN Crypto Audit – Instantly verify if your hardware acceleration (AES-CE, NEON) is actually active for OpenVPN and WireGuard.
- 🛠️ AdGuardHome Control Center – A central hub to toggle the service, manage UI auto-updates, and bulk-import blocklists or allowlists.
- 🆘 Fail-Safe Recovery – "Industrial" self-healing logic. If your AGH binary or init script goes missing, the script can pull pristine copies directly from the device's /rom to fix the install.
- 📦 Surgical Backups – Precision-tracked backups with 2-digit decimal accuracy. Create, manage, and restore configurations with automated timestamping.
- 💾 Zram Swap Management – Essential for low-RAM travel routers. Easily install and tune compressed RAM swap to prevent out-of-memory crashes.
- 📊 Performance Benchmarks – Real-world testing including stressing CPU cycles, OpenSSL throughput, raw Disk and Memory I/O speeds, and DNS throughput.
- 📋 Secure UCI Viewer – Quick, read-only access to your system config. Check SSIDs, Wi-Fi keys, VPN tunnels, and GoodCloud settings without digging through the CLI.
- 🔄 Native Self-Updater – Stay current without manual downloads. The script checks GitHub on launch and can update itself in place.
- 🆓 GPL-3.0 Licensed – Free, open, and community-driven.

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

```
1️⃣  Show Hardware Information
2️⃣  AdGuardHome Control Center
3️⃣  Manage Zram Swap
4️⃣  System Benchmarks (CPU & Disk)
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

System Benchmarks

```
1️⃣  CPU Stress Test
2️⃣  CPU Benchmark (OpenSSL)
3️⃣  Disk I/O Benchmark
0️⃣  Main menu
```

System Configuation Viewer

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

The toolkit includes a built-in update checker (option 7 or automatic on start).

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
No other files are installed by default. If you installed packages via the script (zram-swap, stress, etc.), remove them manually if desired:
```
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
