#!/bin/sh
# GL.iNet Router Toolkit
# Author: phantasm22
# License: GPL-3.0
# Version: 2026-02-15
#
# This script provides system utilities for GL.iNet routers including:
# - Hardware information display with pagination
# - AdGuardHome management (UI updates, storage limits, lists)
# - Zram swap configuration
# - CPU stress testing and benchmarking
# - Disk I/O benchmarking
# - System configuration viewer

# -----------------------------
# Color & Emoji
# -----------------------------
RESET="\033[0m"
CYAN="\033[36m"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
GREY="\033[90m"
BOLD="\033[1m"
BLUE="\033[38;5;153m"

SPLASH="
   _____ _          _ _   _      _   
  / ____| |        (_) \\ | |    | |  
 | |  __| |  ______ _|  \\| | ___| |_ 
 | | |_ | | |______| | . \` |/ _ \\ __|
 | |__| | |____    | | |\\  |  __/ |_ 
  \\_____|______|   |_|_| \\_|\\___|\\__|

         GL.iNet Router Toolkit
"

# -----------------------------
# Global Variables
# -----------------------------
AGH_INIT="/etc/init.d/adguardhome"
AGH_DISABLED=0  # 0 = Available, 1 = Missing/Uninstalled
BLA_BOX="┤ ┴ ├ ┬"
opkg_updated=0
SCRIPT_URL="https://raw.githubusercontent.com/phantasm22/GL-iNet_utils/refs/heads/main/glinet_utils.sh"
TMP_NEW_SCRIPT="/tmp/glinet_utils_new.sh"
SCRIPT_PATH="$0"
[ "${SCRIPT_PATH#*/}" != "$SCRIPT_PATH" ] || SCRIPT_PATH="$(pwd)/$SCRIPT_PATH"

# -----------------------------
# Cleanup any previous updates
# -----------------------------
case "$0" in
    *.new)
        ORIGINAL="${0%.new}"
        printf "🧹 Applying update...\n"
        mv -f "$0" "$ORIGINAL" && chmod +x "$ORIGINAL"
        printf "✅ Update applied. Restarting main script...\n"
        sleep 3
        exec "$ORIGINAL" "$@"
        ;;
esac

# -----------------------------
# Utility Functions
# -----------------------------
press_any_key() {
    printf "\nPress any key to continue... "
    read -rsn1
    printf "\n"
}

read_single_char() {
    read -rsn1 char
    printf "%s" "$char"
}

print_centered_header() {
    title="$1"
    width=48
    title_display_len=${#title}
    case "$title" in
        *[🖥️📡🌐🔒⚙️💾📊🛡️📋☁️]*) title_display_len=$((title_display_len - 2)) ;;
    esac
    
    padding=$(((width - title_display_len) / 2))
    padding_right=$((width - padding - title_display_len))
    
    printf "\n%b\n" "${CYAN}┌────────────────────────────────────────────────┐${RESET}"
    printf "%b" "${CYAN}│"
    printf "%*s" $padding ""
    printf "%s" "$title"
    printf "%*s" $padding_right ""
    printf "%b\n" "│${RESET}"
    printf "%b\n\n" "${CYAN}└────────────────────────────────────────────────┘${RESET}"
}

print_success() {
    printf "%b\n" "${GREEN}✅ $1${RESET}"
}

print_error() {
    printf "%b\n" "${RED}❌ $1${RESET}"
}

print_warning() {
    printf "%b\n" "${YELLOW}⚠️  $1${RESET}"
}

print_info() {
    printf "%b\n" "${BLUE}ℹ️  $1${RESET}"
}

# Helper: Secure Password Input with Asterisks
get_password() {
    local prompt="$1"
    local password=""
    local char=""
    local backspace=$(printf '\177')
    local ctrl_h=$(printf '\b')

    printf "%s" "$prompt" >&2  
    while :; do
        read -s -n 1 char
        if [ -z "$char" ] || [ "$char" = "$(printf '\r')" ]; then
            break
        fi

        if [ "$char" = "$backspace" ] || [ "$char" = "$ctrl_h" ]; then
            if [ ${#password} -gt 0 ]; then
                password="${password%?}"
                printf "\b \b" >&2
            fi
        else
            password="$password$char"
            printf "*" >&2
        fi
    done
    printf "\n" >&2
    printf "%s" "$password" 
}

# -----------------------------
# Self-update function
# -----------------------------
check_self_update() {
    printf "\n🔍 Checking for script updates...\n"

    LOCAL_VERSION="$(grep -m1 '^# Version:' "$SCRIPT_PATH" | awk '{print $3}' | tr -d '\r')"
    [ -z "$LOCAL_VERSION" ] && LOCAL_VERSION="0000-00-00"

    if ! wget -q -O "$TMP_NEW_SCRIPT" "$SCRIPT_URL"; then
        printf "⚠️  Unable to check for updates (network or GitHub issue).\n"
        return 1
    fi

    REMOTE_VERSION="$(grep -m1 '^# Version:' "$TMP_NEW_SCRIPT" | awk '{print $3}' | tr -d '\r')"
    [ -z "$REMOTE_VERSION" ] && REMOTE_VERSION="0000-00-00"

    printf "📦 Current version: %s\n" "$LOCAL_VERSION"
    printf "🌐 Latest version:  %s\n" "$REMOTE_VERSION"

    if [ "$REMOTE_VERSION" \> "$LOCAL_VERSION" ]; then
        printf "\nA new version is available. Update now? [y/N]: "
        read -r ans
        case "$ans" in
            y|Y)
                printf "⬆️  Updating...\n"
                cp "$TMP_NEW_SCRIPT" "$SCRIPT_PATH.new" && chmod +x "$SCRIPT_PATH.new"
                printf "✅ Upgrade complete. Restarting script...\n"
                exec "$SCRIPT_PATH.new" "$@"
                ;;
            *)
                printf "⏭️  Skipping update. Continuing with current version.\n"
                ;;
        esac
    else
        printf "✅ You are already running the latest version.\n"
    fi

    rm -f "$TMP_NEW_SCRIPT" >/dev/null 2>&1
    printf "\n"
}

# -----------------------------
# System Detection Functions
# -----------------------------
ensure_lscpu() {
    if ! command -v lscpu >/dev/null 2>&1; then
        if [ "$opkg_updated" -eq 0 ]; then
            opkg update >/dev/null 2>&1
            opkg_updated=1
        fi
        opkg install lscpu >/dev/null 2>&1
    fi
}

get_cpu_vendor_model() {
    if [ -f /proc/device-tree/compatible ]; then
        result=$(tr '\0' '\n' < /proc/device-tree/compatible 2>/dev/null | grep -iE '^(mediatek|qcom|qca),' | head -1 | sed -E 's/^(mediatek|qcom|qca),/\1 /i; s/mt/MT/i; s/ipq/IPQ/i; s/qca/QCA/i')
        
        if [ -n "$result" ]; then
            printf "%s" "$result"
        else
            printf "Unknown"
        fi
    else
        printf "Unknown"
    fi
}

get_agh_config() {
    if [ ! -f "$AGH_INIT" ]; then
        return 1
    fi
    
    config_path=$(grep -o '\-c [^ ]*' "$AGH_INIT" | awk '{print $2}')
    if [ -n "$config_path" ] && [ -f "$config_path" ]; then
        printf "%s" "$config_path"
        return 0
    fi
    
    return 1
}

get_agh_workdir() {
    if [ ! -f "$AGH_INIT" ]; then
        return 1
    fi
    
    workdir=$(grep -o '\-w [^ ]*' "$AGH_INIT" | awk '{print $2}')
    if [ -n "$workdir" ] && [ -d "$workdir" ]; then
        printf "%s" "$workdir"
        return 0
    fi
    
    return 1
}

is_agh_running() {
    pidof AdGuardHome >/dev/null 2>&1
    return $?
}

# -----------------------------
# Hardware Information Display
# -----------------------------
show_hardware_info() {
    page=1
    total_pages=4
    
    while true; do
        clear
        print_centered_header "Hardware Information"
        printf " ────────────────────────────────────────────────────────────────────\n"
        case $page in
            1)
                printf " %b%bPage 1 of $total_pages: System Overview%b\n\n" "${BOLD}" "${CYAN}" "${RESET}"
                
                printf " %b\n" "${CYAN}System Information:${RESET}"
                if command -v uci >/dev/null 2>&1; then
                    hostname=$(uci get system.@system[0].hostname 2>/dev/null)
                    [ -n "$hostname" ] && printf "   Model: %b%s%b\n" "${GREEN}" "$hostname" "${RESET}"
                fi
                
                if [ -f /etc/glversion ]; then
                    firmware=$(cat /etc/glversion 2>/dev/null)
                    [ -n "$firmware" ] && printf "   Firmware: %b%s%b\n" "${GREEN}" "$firmware" "${RESET}"
                fi
                
                if [ -f /etc/board.json ]; then
                    board=$(grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' /etc/board.json | head -1 | cut -d'"' -f4)
                    [ -n "$board" ] && printf " Board: %b%s%b\n" "${GREEN}" "$board" "${RESET}"
                fi
                printf "\n"
                
                printf " %b\n" "${CYAN}CPU:${RESET}"
                cpu_vendor_model=$(get_cpu_vendor_model)
                printf "   Vendor/Model: %b%s%b\n" "${GREEN}" "$cpu_vendor_model" "${RESET}"
                
                ensure_lscpu
                if command -v lscpu >/dev/null 2>&1; then
                    cpu_cores=$(lscpu 2>/dev/null | grep "^CPU(s):" | awk '{print $2}')
                    cpu_freq=$(lscpu 2>/dev/null | grep "CPU max MHz" | awk '{print $4}')
                    [ -z "$cpu_freq" ] && cpu_freq=$(lscpu 2>/dev/null | grep "CPU MHz" | awk '{print $3}')
                    [ -n "$cpu_cores" ] && printf "   Cores: %b%s%b\n" "${GREEN}" "$cpu_cores" "${RESET}"
                else
                    cpu_cores=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null)
                    [ -n "$cpu_cores" ] && printf "   Cores: %b%s%b\n" "${GREEN}" "$cpu_cores" "${RESET}"
                fi

                if [ -z "$cpu_freq" ]; then
                    case "$cpu_vendor_model" in
                        *MT7981*) cpu_freq="1300" ;; # Beryl AX
                        *MT7986*) cpu_freq="2000" ;; # Flint 2
                    esac
                fi

                [ -n "$cpu_freq" ] && printf "   Frequency: %b%.0f MHz%b\n" "${GREEN}" "$cpu_freq" "${RESET}"

                cpu_load=$(cat /proc/loadavg | awk '{print $1 ", " $2 ", " $3}')
                [ -n "$cpu_load" ] && printf "   Load Average: %b%s%b\n" "${GREEN}" "$cpu_load" "${RESET}"
                
                fan_speed=$(cat /sys/class/hwmon/hwmon*/fan*_input 2>/dev/null | head -1)
                [ -n "$fan_speed" ] && printf "   Fan Speed: %b%s RPM%b\n" "${GREEN}" "$fan_speed" "${RESET}"
                
                printf "\n %b\n" "${CYAN}Memory:${RESET}"
                if [ -f /proc/meminfo ]; then
                    awk '/MemTotal/ {
                        m = $2 / 1024
                        est = m + 30
                        rounded = (int((est + 127) / 128) * 128)
                        printf "   Soldered RAM: '"${GREEN}"'%d MB'"${RESET}"'\n", rounded
                        printf "   Available RAM: '"${GREEN}"'%.0f MB'"${RESET}"'\n", m
                    }' /proc/meminfo
                fi
                printf "\n"
                
                printf " %b\n" "${CYAN}Storage:${RESET}"
                if [ -f /proc/mtd ]; then
                    hex=$(awk 'NR==2 {print $2}' /proc/mtd)
                    if [ -n "$hex" ]; then
                        flash_total=$(printf "%d" "0x$hex" 2>/dev/null)
                        flash_mib=$((flash_total / 1024 / 1024))
                        printf "   Total Physical Flash: %b%d MiB%b\n" "${GREEN}" "$flash_mib" "${RESET}"
                    fi
                fi
                
                printf "\n %b\n" "${CYAN}Filesystem Usage:${RESET}"
                df -h | head -1 | sed 's/^/   /'
                df -h | grep -E "^/dev/" | grep -v "tmpfs" | head -3 | sed 's/^/   /'
                ;;
                
            2)
                printf " %b%bPage 2 of $total_pages: Hardware Crypto Acceleration%b\n\n" "${BOLD}" "${CYAN}" "${RESET}"
                
                cpu_features=$(cat /proc/cpuinfo | grep Features | head -1 | grep -o "aes\|sha1\|sha2\|pmull\|neon" | tr '\n' ' ')
                [ -n "$cpu_features" ] && printf " CPU Features: %b%s%b\n\n" "${GREEN}" "$cpu_features" "${RESET}"
                
                aes_accel="NO"
                chacha_accel="NO"
                poly_accel="NO"
                sha_accel="NO"
                
                if [ -f /proc/crypto ]; then
                    grep -q 'aes-ce\|aes-arm64' /proc/crypto && aes_accel="YES"
                    grep -q 'chacha20-neon' /proc/crypto && chacha_accel="YES"
                    grep -q 'poly1305-neon' /proc/crypto && poly_accel="YES"
                    grep -q 'sha.*-ce' /proc/crypto && sha_accel="YES"
                fi
                
                printf " %b\n" "${CYAN}Hardware-Accelerated Algorithms:${RESET}"
                printf "   AES-CE / ARM64 (OpenVPN) : %b%s%b\n" "$([ "$aes_accel" = "YES" ] && echo "$GREEN" || echo "$RED")" "$aes_accel" "${RESET}"
                printf "   ChaCha20-Neon (WireGuard): %b%s%b\n" "$([ "$chacha_accel" = "YES" ] && echo "$GREEN" || echo "$RED")" "$chacha_accel" "${RESET}"
                printf "   Poly1305-Neon (WireGuard): %b%s%b\n" "$([ "$poly_accel" = "YES" ] && echo "$GREEN" || echo "$RED")" "$poly_accel" "${RESET}"
                printf "   SHA256 / SHA1-CE (System): %b%s%b\n" "$([ "$sha_accel" = "YES" ] && echo "$GREEN" || echo "$RED")" "$sha_accel" "${RESET}"
                
                printf "\n %b\n" "${CYAN}VPN Performance Assessment:${RESET}"
                if [ "$aes_accel" = "YES" ] && [ "$chacha_accel" = "YES" ] && [ "$poly_accel" = "YES" ]; then
                    printf "   %b%s%b\n" "${GREEN}" "   ✅ Both OpenVPN (AES) and WireGuard (ChaCha20+Poly1305)" "${RESET}"
                    printf "   %b%s%b\n" "${GREEN}" "      have hardware acceleration" "${RESET}"
                elif [ "$chacha_accel" = "YES" ] && [ "$poly_accel" = "YES" ]; then
                    printf "   %b%s%b\n" "${YELLOW}" "   ⚠️  WireGuard has HW acceleration, OpenVPN AES does not" "${RESET}"
                else
                    printf "   %b%s%b\n" "${YELLOW}" "   ⚠️  Partial acceleration detected" "${RESET}"
                fi
                ;;
                
            3)
                printf " %b%bPage 3 of $total_pages: Network Interfaces%b\n\n" "${BOLD}" "${CYAN}" "${RESET}"
                
                printf " %b\n" "${CYAN}Ethernet Interfaces:${RESET}"
                ip -br link show 2>/dev/null | grep -E "eth|lan|wan|br-" | while read iface state rest; do
                    speed=""
                    if [ -f "/sys/class/net/$iface/speed" ]; then
                        speed=$(cat /sys/class/net/$iface/speed 2>/dev/null)
                        if [ "$speed" != "-1" ] && [ -n "$speed" ]; then
                            speed=" (${speed}Mbps)"
                        else
                            speed=""
                        fi
                    fi
                    printf "   %s: %b%s%s%b\n" "$iface" "${GREEN}" "$state" "$speed" "${RESET}"
                done
                
                if command -v swconfig >/dev/null 2>&1; then
                    printf "\n %b\n" "${CYAN}Switch Configuration:${RESET}"
                    switch_info=$(swconfig list 2>/dev/null)
                    if [ -n "$switch_info" ]; then
                        printf "   %s\n" "$switch_info"
                    else
                        printf "   No switch detected\n"
                    fi
                fi
                ;;
                
            4)
                printf " %b%bPage 4 of $total_pages: Wireless Interfaces%b\n\n" "${BOLD}" "${CYAN}" "${RESET}"
                
                radio_count=0
                # Use UCI as the source of truth for the Radio list
                for radio in $(uci show wireless | grep "=wifi-device" | cut -d. -f2 | cut -d= -f1); do
                    radio_count=$((radio_count + 1))
                    
                    # 1. Configuration from UCI
                    htmode=$(uci -q get wireless.${radio}.htmode)
                    band=$(uci -q get wireless.${radio}.band)
                    
                    # 2. Map Radio to Interface (ra0, rai0, etc.)
                    iface=""
                    for iface_sec in $(uci show wireless | grep "=wifi-iface" | cut -d. -f2 | cut -d= -f1); do
                        if [ "$(uci -q get wireless.${iface_sec}.device)" = "$radio" ]; then
                            iface=$(uci -q get wireless.${iface_sec}.ifname)
                            break
                        fi
                    done

                    # 3. Real-time Channel Extraction (The Fix)
                    current_chan="N/A"
                    if [ -n "$iface" ] && command -v iwinfo >/dev/null 2>&1; then
                        # This sed regex finds the word 'Channel' and grabs the number following it
                        current_chan=$(iwinfo "$iface" info 2>/dev/null | sed -n 's/.*Channel: \([0-9]*\).*/\1/p')
                    fi
                    
                    # Fallback to UCI config if live data is missing
                    if [ -z "$current_chan" ]; then
                        current_chan=$(uci -q get wireless.${radio}.channel)
                    fi

                    # 4. MIMO Logic
                    mimo="2x2"
                    case "$htmode" in
                        *HE80*|*HE160*|*VHT80*|*VHT160*|*EHT160*|*EHT320*) mimo="4x4" ;;
                        *HE40*|*HE20*|*VHT40*|*VHT20*|*EHT80*) mimo="2x2" ;;
                    esac

                    # 5. Band Display
                    case "$band" in
                        2g) band="2.4GHz" ;;
                        5g) band="5GHz" ;;
                        6g) band="6GHz" ;;
                    esac

                    printf " %bRadio %d: %s%b\n" "${CYAN}" "$radio_count" "$radio" "${RESET}"
                    printf "   Interface: %b%s%b\n" "${GREEN}" "${iface:-N/A}" "${RESET}"
                    printf "   Band:      %b%s%b\n" "${GREEN}" "$band" "${RESET}"
                    printf "   HT Mode:   %b%s%b\n" "${GREEN}" "${htmode:-N/A}" "${RESET}"
                    printf "   MIMO:      %b%s%b\n" "${GREEN}" "$mimo" "${RESET}"
                    printf "   Channel:   %b%s%b\n" "${GREEN}" "${current_chan:-Auto}" "${RESET}"
                    printf "\n"
                done
                ;;
        esac
        
        printf " ────────────────────────────────────────────────────────────────────\n"
        printf " [B] Previous   "
        i=1
        while [ $i -le $total_pages ]; do
            if [ $i -eq $page ]; then
                printf "%b[%d]%b " "${BOLD}" "$i" "${RESET}"
            else
                printf "%b[%d]%b " "${GREY}" "$i" "${RESET}"
            fi
            i=$((i + 1))
        done
        printf "  [N] Next   [0] Main menu  "
        
        nav_choice=$(read_single_char)
        
        case "$nav_choice" in
            b|B) [ $page -gt 1 ] && page=$((page - 1)) ;;
            n|N) [ $page -lt $total_pages ] && page=$((page + 1)) ;;
            1|2|3|4) 
                if [ "$nav_choice" -ge 1 ] 2>/dev/null && [ "$nav_choice" -le $total_pages ]; then
                    page=$nav_choice
                fi
                ;;
            m|M|0) return ;;
        esac
    done
}

# -----------------------------
# AdGuardHome UI Updates Management
# -----------------------------
show_agh_ui_help() {
    clear
    print_centered_header "AdGuardHome UI Updates - Help"
    
    cat << 'HELPEOF'
What does this setting control?
───────────────────────────────
This option controls whether AdGuardHome is allowed to automatically check for and 
download new versions of its web interface (UI) directly from the AdGuard servers.

Two modes:
• ENABLED  → AdGuardHome can update its own UI automatically when a new version is released
• DISABLED → UI updates are blocked (the --no-check-update flag is added)

Why would you want to disable UI updates?
─────────────────────────────────────────
On GL.iNet routers, the recommended approach is often to **disable automatic UI updates** because:

• GL.iNet provides their own pre-packaged, tested version of AdGuardHome
• Auto-updating the UI can sometimes cause compatibility issues with GL.iNet's custom firmware
• It may overwrite GL.iNet-specific patches or branding
• Manual updates through GL.iNet's firmware or opkg are usually safer and better integrated

When should you enable UI updates?
──────────────────────────────────
• You are running a standalone/community-installed AdGuardHome (not the GL.iNet version)
• You want the very latest UI features and fixes as soon as they are released
• You are comfortable troubleshooting potential compatibility problems

Quick recommendation for most GL.iNet users:
• Keep UI Updates **DISABLED** (default safe choice on GL firmware)
• Only enable if you specifically need a newer UI feature and understand the risks

In this menu you can:
1. Enable UI Updates (remove --no-check-update flag + restart AdGuardHome)
2. Disable UI Updates (add --no-check-update flag + restart AdGuardHome)
3. Return to main menu

Note: Changing this setting restarts AdGuardHome automatically if already started. 
      Your filtering rules and stats are preserved.
HELPEOF
    
    press_any_key
}

manage_agh_ui_updates() {
    while true; do
        clear
        print_centered_header "AdGuardHome UI Updates Management"

        agh_pid=$(pidof AdGuardHome)

        printf " %b\n" "${CYAN}CURRENT STATUS${RESET}"
        if [ -z "$agh_pid" ]; then
            printf "   Running: ❌\n"
        else
            printf "   Running: ✅ (PID: %s)\n" "$agh_pid"
        fi

        if grep -q -- "--no-check-update" "$AGH_INIT"; then
            printf "   UI Updates: %bDISABLED%b\n\n" "${RED}" "${RESET}"
        else
            printf "   UI Updates: %bENABLED%b\n\n" "${GREEN}" "${RESET}"
        fi
        
        printf "1️⃣  Enable UI Updates\n"
        printf "2️⃣  Disable UI Updates\n"
        printf "0️⃣  Return to previous menu\n"
        printf "❓ Help\n"
        printf "\nChoose [1-2/0/?]: "
        read -r agh_choice
        printf "\n"
        
        case $agh_choice in
            1)
                if grep -q -- "--no-check-update" "$AGH_INIT"; then
                    sed -i 's/--no-check-update//g; s/  / /g' "$AGH_INIT"
                    print_success "UI updates enabled in AdGuardHome"
                    
                    if is_agh_running; then    
                        $AGH_INIT restart >/dev/null 2>&1
                        if [ $? -eq 0 ]; then
                            print_success "AdGuardHome restarted successfully"
                        else
                            print_error "Failed to restart AdGuardHome"
                        fi
                    fi
                else
                    print_warning "UI updates are already enabled"
                fi
                press_any_key
                ;;
            2)
                if ! grep -q -- "--no-check-update" "$AGH_INIT"; then
                    sed -i '/procd_set_param command/ s/ -c/ --no-check-update -c/' "$AGH_INIT"
                    print_success "UI updates disabled in AdGuardHome"
                    
                    if is_agh_running; then    
                        $AGH_INIT restart >/dev/null 2>&1
                        if [ $? -eq 0 ]; then
                            print_success "AdGuardHome restarted successfully"
                        else
                            print_error "Failed to restart AdGuardHome"
                        fi
                    fi
                else
                    print_warning "UI updates are already disabled"
                fi
                press_any_key
                ;;
            \?|h|H|❓)
                show_agh_ui_help
                ;;
            m|M|0)
                return
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# -----------------------------
# AdGuardHome Storage Management
# -----------------------------
show_agh_storage_help() {
    clear
    print_centered_header "AdGuardHome Filter Size Limit - Help"
    
    cat << 'HELPEOF'
AdGuardHome Filter Size Limit – BE3600 & Similar Models

Why the limit exists
────────────────────
On 512MB RAM routers (MT3600BE, some newer GL models), GL.iNet creates a 10MB file 
and mounts it as /etc/AdGuardHome/data/filters. This caps filter cache size to 
prevent AdGuardHome from consuming too much RAM and crashing the router.

Removing this limit lets you use bigger blocklists (e.g. HaGeZi Pro++, multi-list setups), 
but significantly increases RAM usage when filters are loaded/updated.

Risks if you remove it without mitigation
─────────────────────────────────────────
• High RAM pressure → router slowdown, OOM killer, or crashes
• Especially bad with many clients, VPN, or heavy filtering

Strong recommendation
─────────────────────
Enable **zram swap** first (Toolkit → option 4: Manage Zram Swap → Install & Enable).  
Zram gives fast compressed swap in RAM, greatly reduces memory pressure, 
and is safe for most GL.iNet 512MB devices.

Only remove the 10MB limit after zram is active.
HELPEOF
    
    press_any_key
}

manage_agh_storage() {
    while true; do
        clear
        print_centered_header "AdGuardHome Storage Management"

        AGH_WORKDIR=$(get_agh_workdir)
        if [ -z "$AGH_WORKDIR" ]; then
            print_error "Could not find AdGuardHome working directory"
            printf "\n"
            press_any_key
            return
        fi
        
        printf " %b\n" "${CYAN}STORAGE STATUS${RESET}"
        printf "   Working Directory: %b%s%b\n\n" "${GREEN}" "$AGH_WORKDIR" "${RESET}"
        
         if [ -d "$AGH_WORKDIR/data" ]; then
            printf  " %b\n" "${CYAN}$AGH_WORKDIR/data Directory:${RESET}"
            df -h "$AGH_WORKDIR/data" 2>/dev/null | tail -1 | awk '{printf "   Total: %s | Used: %s | Free: %s\n", $2, $3, $4}'
        fi
        
        if [ -d "$AGH_WORKDIR/data/filters" ]; then
            printf "\n %b\n" "${CYAN}$AGH_WORKDIR/data/filters Directory:${RESET}"
            df -h "$AGH_WORKDIR/data/filters" 2>/dev/null | tail -1 | awk '{printf "   Total: %s | Used: %s | Free: %s\n", $2, $3, $4}'
        fi     
        
        limit_active=0
        if grep -q "mount_filter_img" "$AGH_INIT" 2>/dev/null && ! grep -q "^[[:space:]]*#.*mount_filter_img" "$AGH_INIT" 2>/dev/null; then
            limit_active=1
            printf "   Filter Size Limit: %bACTIVE (10MB)%b\n" "${YELLOW}" "${RESET}"
        else
            printf "   Filter Size Limit: %bINACTIVE%b\n" "${GREEN}" "${RESET}"
        fi
        
        printf "\n1️⃣  Remove Filter Size Limitation\n"
        printf "2️⃣  Re-enable Filter Size Limitation\n"
        printf "0️⃣  Return to previous menu\n"
        printf "❓ Help\n"
        printf "\nChoose [1-2/0/?]: "
        read -r storage_choice
        printf "\n"
        
        case $storage_choice in
            1)
                if [ $limit_active -eq 0 ]; then
                    print_warning "Filter size limitation is already removed"
                    press_any_key
                    continue
                fi
                
                cat << 'WARNEOF'
GL.iNet (MT3600BE & similar models) limits AdGuardHome filter cache to 10MB 
by creating a small tmpfs/loop-mounted partition at /etc/AdGuardHome/data/filters.

Removing this limit allows larger/more filter lists, but may cause high RAM usage 
and instability on 512MB devices when filters are big or many are enabled.
WARNEOF
                
                if ! swapon -s 2>/dev/null | grep -q zram; then
                    print_warning "WARNING: Zram swap is NOT enabled!"
                    printf "%b\n\n" "${YELLOW}Strongly recommended: Enable zram swap first${RESET}"
                    printf "%b\n" "${YELLOW}→ it gives fast compressed swap in RAM and protects flash.${RESET}"
                fi
                
                printf "\n%b" "${YELLOW}Remove the 10MB limit anyway? [y/N]: ${RESET}"
                read -r confirm
                if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                    printf "Operation cancelled.\n"
                    press_any_key
                    continue
                fi
                
                if is_agh_running; then
                    agh_pid=$(pidof AdGuardHome)
                    $AGH_INIT stop >/dev/null 2>&1
                else
                    agh_pid=""
                fi

                loop_dev=$(mount | grep "$AGH_WORKDIR/data/filters" | awk '{print $1}')
                if [ -n "$loop_dev" ]; then
                    umount "$loop_dev" 2>/dev/null
                    print_success "Unmounted filter partition"
                fi
                
                if [ -f "$AGH_WORKDIR/data.img" ]; then
                    rm -f "$AGH_WORKDIR/data.img"
                    print_success "Removed data.img file"
                fi
                
                sed -i '/^[[:space:]]*mount_filter_img/s/^/# /' "$AGH_INIT"
                print_success "Disabled mount_filter_img in init script"
                
                if [ -n "$agh_pid" ]; then
                    $AGH_INIT start >/dev/null 2>&1
                    if [ $? -eq 0 ]; then
                        print_success "AdGuardHome restarted successfully"
                        print_success "Filter size limit removed!"
                    else
                        print_error "Failed to restart AdGuardHome"
                    fi
                fi
                
                press_any_key
                ;;
            2)
                if ! grep -q "mount_filter_img" "$AGH_INIT"; then
                    print_warning "Filter size limitation feature (mount_filter_img) does not exist on this device/firmware."
                    printf "   No changes possible — your AdGuardHome is not restricted by the filter size limit.\n"
                    press_any_key
                    continue
                fi

                if ! grep -q "^#.*mount_filter_img" "$AGH_INIT"; then
                    print_warning "Filter size limitation is already active (mount_filter_img is not commented out)."
                    press_any_key
                    continue
                fi
                
                if is_agh_running; then
                    agh_pid=$(pidof AdGuardHome)
                    $AGH_INIT stop >/dev/null 2>&1
                else
                    agh_pid=""
                fi
                
                sed -i '/mount_filter_img/s/^[[:space:]]*#[[:space:]]*//' "$AGH_INIT"
                print_success "Re-enabled mount_filter_img in init script"
                
                if [ -n "$agh_pid" ]; then
                    $AGH_INIT start >/dev/null 2>&1
                    if [ $? -eq 0 ]; then
                        print_success "AdGuardHome restarted successfully"
                        printf "\n%b\n" "${GREEN}✅ Filter size limit removed!${RESET}"
                    else
                        print_error "Failed to restart AdGuardHome"
                    fi
                fi
                
                press_any_key
                ;;
            \?|h|H|❓)
                show_agh_storage_help
                ;;
            m|M|0)
                return
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# -----------------------------
# AdGuardHome Lists Management
# -----------------------------
show_agh_lists_help() {
    clear
    print_centered_header "AdGuardHome Lists - Help"
    
    cat << 'HELPEOF'
What are these lists?
────────────────────────────────────────────────────────────────────────
This option installs custom DNS filter lists for AdGuardHome to enhance 
ad blocking and streaming compatibility:

- **Phantasm22's Blocklist**:
  Blocks Amazon Echo Show ads. Derived from HaGeZi's Pro++ for broad 
  protection, curated for GL.iNet performance. (Auto-updates, GPL-3.0).
  URL: https://github.com/phantasm22/AdGuardHome-Lists/blocklist.txt

- **Phantasm22's Allow List**:
  Unblocks domains for Roku, Apple TV, NBC, Peacock, Hulu, Disney+, 
  YouTube, Prime, Max, and more. Prevents false positives.
  URL: https://github.com/phantasm22/AdGuardHome-Lists/allowlist.txt

- **HaGeZi's Pro++ Blocklist**:
  Aggressive protection against ads, tracking, phishing, and malware.
  Part of the Multi series (230k+ entries). Strict protection; 
  best for users comfortable whitelisting if rare breaks occur.

Why HaGeZi's Pro++ as the default base?
────────────────────────────────────────────────────────────────────────
It provides comprehensive protection and balances aggressive blocking 
with usability. Users report ~2x more blocks than alternatives like 
OISD with minimal false positives. It is highly regarded on Reddit, 
NextDNS, and Pi-hole forums for privacy gains.

These lists auto-update in AdGuardHome. Install for enhanced blocking—
monitor for streaming breaks and whitelist via the AdGuardHome UI.
HELPEOF
    
    press_any_key
}

manage_agh_lists() {
    LIST_REGISTRY="1|Phantasm22's Blocklist|Blocklist|https://raw.githubusercontent.com/phantasm22/AdGuardHome-Lists/refs/heads/main/blocklist.txt
2|HaGeZi's Pro++ Blocklist|Blocklist|https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.plus.txt
3|Phantasm22's Allow List|Allowlist|https://raw.githubusercontent.com/phantasm22/AdGuardHome-Lists/refs/heads/main/allowlist.txt"

    while true; do
        clear
        print_centered_header "AdGuardHome Lists Manager"

        AGH_CONFIG=$(get_agh_config)
        [ -z "$AGH_CONFIG" ] && { print_error "Config not found"; press_any_key; return; }
        
        LISTS_DATA=$(mktemp -t agh_data.XXXXXX)

        # ---------------------------------------------------------
        # 1. PARSING (Fixed for + signs and quotes)
        # ---------------------------------------------------------
        while IFS='|' read -r r_id r_name r_type r_url; do
			status_val=$(awk -v n="$r_name" '
                BEGIN { RS = "[[:space:]]*- "; FS = "\n" }
                # index() does a literal string search. It ignores plus signs and quotes.
                index($0, "name: " n) || index($0, "name: \"" n "\"") {
                    if ($0 ~ "enabled: true") { print "true"; exit }
                    if ($0 ~ "enabled: false") { print "false"; exit }
                }
			' "$AGH_CONFIG")
    		status=0; [ "$status_val" = "false" ] && status=1; [ "$status_val" = "true" ] && status=2
    		printf "%s|%s|%s|%s|1|1|%s\n" "$r_id" "$r_name" "$r_type" "$status" "$r_url" >> "$LISTS_DATA"
done <<EOF
$LIST_REGISTRY
EOF

        local next_idx=$(($(echo "$LIST_REGISTRY" | wc -l) + 1))
        awk '
            /^filters:/ || /^whitelist_filters:/ {in_sec=1; type=($1=="filters:"?"Blocklist":"Allowlist")}
            /^[a-z_]+:/ && !/^filters:/ && !/^whitelist_filters:/ {in_sec=0}
            in_sec && /name: / {
                gsub(/^[[:space:]]*name:[[:space:]]*/, "");
                gsub(/^"|",?$/, "");
                if ($0 != "") print type "|" $0
            }
        ' "$AGH_CONFIG" | while IFS='|' read -r c_type c_name; do
			if ! grep -q "|$c_name|" "$LISTS_DATA"; then
                status_val=$(awk -v n="$c_name" '
                    BEGIN { RS = "[[:space:]]*- "; FS = "\n" } 
                    $0 ~ "name: [\" ]*" n "[\" ]*" {
                        if ($0 ~ "enabled: true") { print "true"; exit }
                        if ($0 ~ "enabled: false") { print "false"; exit }
                    }
                ' "$AGH_CONFIG")
				status=1; [ "$status_val" = "true" ] && status=2
                printf "%s|%s|%s|%s|0|0|CUSTOM\n" "$next_idx" "$c_name" "$c_type" "$status" >> "$LISTS_DATA"
                next_idx=$((next_idx + 1))
            fi
        done

        # ---------------------------------------------------------
        # 2. UI LOOP
        # ---------------------------------------------------------
        while true; do
            clear
            print_centered_header "AdGuardHome Lists Manager"
            printf " Sel.  %-12s %-50s %-20s\n" "Type" "Name" "Status"
            printf " ──────────────────────────────────────────────────────────────────────────────────────────\n"
            while IFS='|' read -r idx name type stat sel rec url; do
                s_box="[ ]  "; [ "$sel" -eq 1 ] && s_box="[✓]  "
                case "$stat" in 0) s_txt="Missing" ;; 1) s_txt="Installed (inactive)" ;; 2) s_txt="Installed (active)" ;; esac
                label="$idx. $name"; [ "$rec" -eq 1 ] && label="$label ★"
                [ "$rec" -eq 1 ] && label=$(printf "%-52s" "$label") || label=$(printf "%-50s" "$label")
                printf " %-4s %-12s %-50s %-20s\n" "$s_box" "$type" "$label" "$s_txt"
            done < "$LISTS_DATA"
            printf " ──────────────────────────────────────────────────────────────────────────────────────────\n"
            printf " [A] All   [N] None   [T#] Toggle   [C] Confirm   [0] Cancel   [?] Help\n"
            printf " Enter command: "
            read -r input

            case "$input" in
                a|A) sed -i 's/\(.*|.*|.*|.*|\)0\(|.*|.*\)/\11\2/' "$LISTS_DATA" ;;
                n|N) sed -i 's/\(.*|.*|.*|.*|\)1\(|.*|.*\)/\10\2/' "$LISTS_DATA" ;;
                t*|T*)
                    num=$(echo "$input" | sed 's/[tT]//g')
                    [ -n "$num" ] && awk -F'|' -v t="$num" 'BEGIN{OFS="|"} {if($1==t) $5=($5==1?0:1); print}' "$LISTS_DATA" > "$LISTS_DATA.tmp" && mv "$LISTS_DATA.tmp" "$LISTS_DATA"
                    ;;
                c|C)
                    to_install=$(awk -F'|' '$5==1 && $4==0' "$LISTS_DATA")
                    to_remove=$(awk -F'|' '$5==0 && $4!=0' "$LISTS_DATA")
                    
					if [ -z "$to_install" ] && [ -z "$to_remove" ]; then
                        print_warning "No changes to apply (Selection matches current status)"
                        sleep 2
                        break 
                    fi

					# 3. CONFIRMATION SCREEN
					clear
                    print_centered_header "Confirm List Changes"
                    [ -n "$to_install" ] && { printf "${GREEN}TO BE INSTALLED:${RESET}\n"; echo "$to_install" | cut -d'|' -f2 | sed 's/^/  + /'; }
                    [ -n "$to_remove" ] && { printf "\n${RED}TO BE REMOVED:${RESET}\n"; echo "$to_remove" | cut -d'|' -f2 | sed 's/^/  - /'; }
                    
                    printf "\nProceed with changes? [y/N]: "; read -r confirm
                    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && break

                    # 4. BACKUP CREATION
                    stamp=$(date +%Y%m%d%H%M%S)
                    BACKUP_FILE="${AGH_CONFIG}.backup.${stamp}"
                    cp "$AGH_CONFIG" "$BACKUP_FILE"

                    $AGH_INIT stop >/dev/null 2>&1

                   	# 5. REMOVAL (Your logic, hardened for line order)
					echo "$to_remove" | while IFS='|' read -r i n t s sel rec u; do
						
						# 1. Find the exact line number of the name escaping special chars (e.g. +) and optional quotes
						n=$(echo "$n" | sed 's/+/\\+/g; s/\./\\./g')
						name_line=$(grep -nE "name: \"?$n\"?" "$AGH_CONFIG" | cut -d: -f1 | head -n1)
						
						if [ -n "$name_line" ]; then
							# 2. Find the nearest "- enabled:" ABOVE that name line
							# This ensures we hit the start of THE SPECIFIC block
							start_del=$(sed -n "1,${name_line}p" "$AGH_CONFIG" | grep -n "enabled:" | tail -n1 | cut -d: -f1)
							
							# 3. Delete 4 lines starting from that "- enabled" line
							if [ -n "$start_del" ]; then
								sed -i "${start_del},$((start_del + 3))d" "$AGH_CONFIG"
							fi
						fi
					done

                    # 6. INSTALLATION
					if [ -n "$to_install" ]; then
						count=0
						echo "$to_install" | while IFS='|' read -r i n t s sel rec u; do
							[ -z "$u" ] || [ "$u" = "CUSTOM" ] && continue
							
							ts="$(( $(date +%s) - 1769040000 ))$count"
							
							new_block="- enabled: true\\
url: $u\\
name: \"$n\"\\
id: $ts"

							target_head="filters:"
							[ "$t" = "Allowlist" ] && target_head="whitelist_filters:"

							# Remove empty array brackets if they exist
							sed -i "s/^$target_head \[\]/$target_head/" "$AGH_CONFIG"
							
							# Append the new block directly after the header line
							sed -i "/^$target_head/a $new_block" "$AGH_CONFIG"

							# Force 2 spaces for dash, 4 for children
							sed -i "s/^- enabled:/  - enabled:/" "$AGH_CONFIG"
							sed -i "s/^url:/    url:/" "$AGH_CONFIG"
							sed -i "s/^name:/    name:/" "$AGH_CONFIG"
							sed -i "s/^id:/    id:/" "$AGH_CONFIG"
							
							count=$((count + 1))
						done
					fi

					# 7. CLEANUP (Strict Header Matching)
					for head in "filters" "whitelist_filters"; do
						# Match the header only at the start of a line to avoid 'filtering_enabled' etc.
						if grep -qE "^$head:|^  $head:" "$AGH_CONFIG"; then
							# Check the line immediately following the specific header
							# We use -A 1 to see the 'After' line
							next_line=$(grep -A 1 -E "^$head:|^  $head:" "$AGH_CONFIG" | tail -n 1)
							
							# If the next line isn't a list item (- enabled), the section is empty or broken
							if ! echo "$next_line" | grep -q "\- enabled:"; then
								# Force the header to empty array and ensure no hanging fragments remain
								sed -i "/^$head:/ s/.*/$head: []/" "$AGH_CONFIG"
								sed -i "/^  $head:/ s/.*/  $head: []/" "$AGH_CONFIG"
							fi
						fi
					done

                    # 8. RESTART & ERROR RECOVERY
                    $AGH_INIT start >/dev/null 2>&1
                    sleep 2
                    if ! pidof AdGuardHome >/dev/null; then
                        printf "\n"
						print_error "AdGuardHome failed to start! Reverting..."
                        cp "$AGH_CONFIG" "${AGH_CONFIG}.error.${stamp}"
                        cp "$BACKUP_FILE" "$AGH_CONFIG"
                        $AGH_INIT start >/dev/null 2>&1
                        if ! pidof AdGuardHome >/dev/null; then
                            print_error "FATAL: Could not restore AGH even with backup!"
                        else
                            print_warning "Restoring last known good configuration."
							print_success "AdGuardHome restarted successfully with restored config"
                        fi
                    else
                        printf "\n"
						print_success "Changes applied" 
						print_success "Backup file created: $(basename $BACKUP_FILE)"
						print_success "AdGuardHome restarted successfully with new configuration"
                    fi
                    press_any_key; rm -f "$LISTS_DATA"; break 1
                    ;;
                \?|h|H|❓)
                    show_agh_lists_help ;;
                0) rm -f "$LISTS_DATA"; return ;;
            esac
        done
    done
}

# -----------------------------
# AdGuardHome Direct Access Management
# -----------------------------

show_agh_direct_help() {
    clear
    print_centered_header "Direct Access Help"
    cat << 'HELPEOF'

1. TOGGLE DIRECT ACCESS: 
   - ON: Access AGH at http://192.168.8.1:3000 bypassing GL.iNet UI.
   - OFF: Port 3000 redirects to Port 80 (Standard GL.iNet Login).

2. WEB UI CREDENTIALS:
   - Uses 'apache-utils' to generate a secure Bcrypt hash.
   - This is necessary to prevent open access to your dashboard
     once you bypass the GL.iNet login gatekeeper.

3. REMOVE PASSWORD:
   - Sets 'users: []' in the config.yaml. 
   - Useful if you want the dashboard to be entirely open on LAN.

NOTES:
I.  BACKUPS: Automatically creates .backup.YYYYMMDDHHMMSS for
    both the /etc/init.d script and the config.yaml.
II. PERSISTENCE: GL.iNet firmware updates will overwrite the
    init script. Simply run Option 1 again to restore access.

HELPEOF
    press_any_key
}

update_agh_credentials() {
    clear
    print_centered_header "Set Web UI Credentials"
    if [ "$PASS_STATUS" = "✅" ]; then
        print_warning "A password is already set. Proceeding will overwrite it.\n"
    else 
        print_warning "No password currently set. This will create a new username and password.\n"
    fi
    printf "Confirm to proceed? [y/N]: "
    read -r confirm
    printf "\n"
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return

    # Dependency Check
    if ! command -v htpasswd >/dev/null 2>&1; then
        printf "🔍 Installing apache-utils...\n"
        opkg update >/dev/null 2>&1 && opkg install apache-utils >/dev/null 2>&1
        if ! command -v htpasswd >/dev/null 2>&1; then
            print_error "Failed to install apache-utils. Cannot proceed."
            press_any_key
            return
        fi
    fi

    # Input capture
    printf "Enter Username: "
    read -r user_name
    while true; do
        user_pass=$(get_password "Enter Password: ")

        # Check for exit command to allow user to cancel out of password entry
        case "$user_pass" in
            [Ee][Xx][Ii][Tt]) 
                print_warning "Operation cancelled by user."
                return 
                ;;
        esac

        # 2. Check for empty password immediately after the first entry
        if [ -z "$user_pass" ]; then
            print_error "Password cannot be empty."
            continue
        fi

        # 3. Replace the confirmation read block
        user_pass_conf=$(get_password "Confirm Password: ")

        # 4. Final match check
        if [ "$user_pass" = "$user_pass_conf" ]; then
            printf "\n"
            break
        fi
        printf "\n"
        print_error "Passwords do not match. Try again or type \"exit\" to cancel."

    done

    BCRYPT_HASH=$(htpasswd -n -B -b "$user_name" "$user_pass" | cut -d: -f2)

    # --- VALIDATION LOGIC ---
    [ -z "$TIMESTAMP" ] && TIMESTAMP=$(date +%Y%m%d%H%M%S)
    BACKUP_FILE="$AGH_CONF.backup.$TIMESTAMP"
    cp "$AGH_CONF" "$BACKUP_FILE"
    
    if grep -q "users: \[\]" "$AGH_CONF"; then
        # Case A: Empty list. Replace line with block.
        sed -i "/users: \[\]/c\users:\n  - name: $user_name\n    password: \"$BCRYPT_HASH\"" "$AGH_CONF"
    elif grep -q "^users:" "$AGH_CONF"; then
        # Case B: Check if next two lines are - name and password
        line_num=$(grep -n "^users:" "$AGH_CONF" | cut -d: -f1)
        check_name=$(sed -n "$((line_num+1))p" "$AGH_CONF")
        check_pass=$(sed -n "$((line_num+2))p" "$AGH_CONF")

        if echo "$check_name" | grep -q " - name:" && echo "$check_pass" | grep -q "password:"; then
            sed -i "$((line_num+1))s/- name: .*/- name: $user_name/" "$AGH_CONF"
            sed -i "$((line_num+2))s|password: .*|password: \"$BCRYPT_HASH\"|" "$AGH_CONF"
        else
            print_error "Unexpected YAML structure detected below 'users:' line."
            print_warning "Manual edit required to avoid corrupting config."
            press_any_key; return
        fi
    else
        print_error "Could not find 'users:' key in $AGH_CONF"
        press_any_key; return
    fi

    # --- RESTART & RECOVERY ---
    $AGH_INIT stop >/dev/null 2>&1
    $AGH_INIT start >/dev/null 2>&1
    sleep 2
    if ! pidof AdGuardHome >/dev/null; then
        print_error "Service failed to start! Rolling back..."
        cp "$BACKUP_FILE" "$AGH_CONF"
        $AGH_INIT start >/dev/null 2>&1
        press_any_key
    else
        print_success "Credentials updated. Backup created: $(basename "$BACKUP_FILE")"
        press_any_key
    fi
}

manage_agh_direct_access() {
    while true; do
        clear
        print_centered_header "AdGuardHome Direct Access"
        lan_ipaddr=$(uci get network.lan.ipaddr 2>/dev/null)
        AGH_CONF=$(get_agh_config)
        DIRECT_STATUS="❌"
        grep -q -- "--glinet" "$AGH_INIT" || DIRECT_STATUS="✅"
        
        PASS_STATUS="✅"
        grep -q "users: \[\]" "$AGH_CONF" && PASS_STATUS="❌"
        
        printf " ${CYAN}STATUS${RESET}\n"
        printf "   Direct WebUI Access: %b" "$DIRECT_STATUS\n"
        printf "   WebUI Username / Password Set: %b" "$PASS_STATUS\n\n"
        printf "1️⃣  Toggle Direct Access (Standalone vs Integrated)\n"
        printf "2️⃣  Add/Update Web UI Credentials (Username/Password)\n"
        printf "3️⃣  Remove Web UI Password (Set to Open Access)\n"
        printf "0️⃣  Return to previous menu\n"
        printf "❓ Help\n"
        
        printf "\nChoose [1-3/0/?]: "
        read -r direct_choice
        TIMESTAMP=$(date +%Y%m%d%H%M%S)

        case $direct_choice in
            1)
                clear
                if [ "$DIRECT_STATUS" = "❌" ]; then
                    print_centered_header "Enable AdGuardHome Direct Access"
                    print_warning "AdGuardHome direct access bypasses GL.iNet Web UI security.\n"
                    print_warning "If no password is set, and you bypass setting a password, the UI will be ${BOLD}UNSECURED.${RESET}\n"
                    print_info "Once enabled, you can access AdGuardHome Web UI at ${BOLD}http://$lan_ipaddr:3000${RESET}\n"
                    printf "Proceed with enabling? [y/N]: "
                else
                    print_centered_header "Disable AdGuardHome Direct Access"
                    print_warning "AdGuardHome direct Web UI access via http://$lan_ipaddr:3000 will be disabled.\n"
                    print_warning "Any passwords set will remain but will be bypassed.\n"
                    print_info "Once disabled, you can access the AdGuardHome Web UI at: ${BOLD}http://$lan_ipaddr/${RESET}\n"
                    printf "Proceed with disabling? [y/N]: "
                fi
                read -r confirm
                printf "\n"
                [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue
                
                cp "$AGH_INIT" "$AGH_INIT.backup.$TIMESTAMP"
                
                if [ "$DIRECT_STATUS" = "✅" ]; then
                    # Turning Direct Access OFF (Integrated Mode)
                    sed -i 's/AdGuardHome /AdGuardHome --glinet /g' "$AGH_INIT"
                    $AGH_INIT restart >/dev/null 2>&1
                    print_success "Direct Access Disabled (Integrated Mode)"
                    press_any_key
                else
                    # Turning Direct Access ON (Standalone Mode)
                    sed -i 's/ --glinet//g' "$AGH_INIT"
                    print_success "Direct Access Enabled (Standalone Mode)"
                    
                    if [ "$PASS_STATUS" = "❌" ]; then
                        printf "\n"
                        print_warning "No username/password has been set for AdGuardHome.\n"
                        printf "Would you like to set one now? [Y/n]: "
                        read -r set_pass
                        printf "\n"
                        if [ "$set_pass" != "n" ] && [ "$set_pass" != "N" ]; then
                            update_agh_credentials && continue
                        else
                            $AGH_INIT restart >/dev/null 2>&1
                            print_warning "AdGuardHome restarted with unsecured access."
                            press_any_key
                        fi
                    else
                        $AGH_INIT restart >/dev/null 2>&1
                        print_success "AdGuardHome restarted successfully."
                        press_any_key
                    fi
                fi
                ;;

            2) update_agh_credentials;;  

            3)
                clear
                print_centered_header "Remove AdGuardHome Web UI Password"
                if [ "$PASS_STATUS" = "❌" ]; then
                    print_warning "No password currently exists."
                    press_any_key; continue
                fi
                if [ "$DIRECT_STATUS" = "✅" ]; then
                    print_warning "Remove credentials and enable OPEN ACCESS (Unsecured) to AdGuardHome Web UI?"
                else
                    print_warning "Remove credentials to AdGuardHome Web UI?"
                fi
                printf "\n"
                printf "Confirm [y/N]: "
                read -r confirm
                printf "\n"
                [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue

                BACKUP_FILE="$AGH_CONF.backup.$TIMESTAMP"
                cp "$AGH_CONF" "$BACKUP_FILE"
                $AGH_INIT stop >/dev/null 2>&1

                # Find users: block and replace with users: []
                line_num=$(grep -n "^users:" "$AGH_CONF" | cut -d: -f1)
                # Delete the next two lines (- name and password) then change users: to users: []
                if ! grep -q "users: \[\]" "$AGH_CONF"; then
                    sed -i "$((line_num+1)),$((line_num+2))d" "$AGH_CONF"
                fi
                sed -i "${line_num}s/users:.*/users: []/" "$AGH_CONF"

                $AGH_INIT start >/dev/null 2>&1
                sleep 2
                if ! pidof AdGuardHome >/dev/null; then
                    print_error "Service failed to start! Rolling back..."
                    cp "$BACKUP_FILE" "$AGH_CONF"
                    $AGH_INIT start >/dev/null 2>&1
                    press_any_key
                else
                    print_success "Password removed. Service restarted."
                    press_any_key
                fi
                ;;

            0) return ;;
            \?|h|H|❓) show_agh_direct_help ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}


# -----------------------------
# AdGuardHome Control Center
# -----------------------------

show_agh_help() {
    clear
    print_centered_header "AdGuardHome Hub - Help"
    cat << 'HELPEOF'
1. SETUP & CONFIG: Manages UI entry points (Direct Access), binary
   lifecycle (Updates), and storage thresholds (10MB Limit).

2. BACKUP SUITE: 
   - SAVE: Generates timestamped sync points for Config and Binary.
   - RESTORE: Allows modular injection of previous system states.
   - MANAGE: Cleanup utility to purge redundant backup files.

3. SERVICE & HEALTH:
   - POWER: Toggles the daemon runtime (On/Off/Restart).
   - LOGS: Real-time 'logread' stream for diagnostic observation.
   - CACHE: Flushes filter data to resolve download/checksum errors.

CL. FACTORY RESET: Reconstructs the environment using read-only
    firmware defaults located in the /rom partition.

NOTES:
- RULE DISCREPANCY: 'Raw' counts include all text lines. The WebUI 
  displays a lower 'Optimized' count after deduplication.
- 10MB LIMIT: Crucial for routers with small flash storage. When
  active, it restricts filter size to prevent storage exhaustion.
- LOGS: Query logs are often in /tmp (RAM). If 'Free Space' is 
  low, the system may become unstable.
HELPEOF
    press_any_key
}

create_agh_backup() {
    local ts=$(date +%Y%m%d%H%M%S)
    local b_cfg="Y"
    local b_bin="N"
    local b_ini="N"
    local AGH_CONFIG=$(get_agh_config)

    while true; do
        clear
        print_centered_header "AdGuardHome Backup Creation"
        printf " TIMESTAMP: $ts\n"
        printf " ────────────────────────────────────────────────────────────\n"
        printf " 1. [ %s ] Configuration Settings (YAML)\n" "$b_cfg"
        printf " 2. [ %s ] App Binary (AdGuardHome Executable)\n" "$b_bin"
        printf " 3. [ %s ] Startup Script (init.d)\n\n" "$b_ini"
        printf " ────────────────────────────────────────────────────────────\n"
        printf " [#] Toggle Component   [S] Save Backup   [0] Cancel\n"
        printf " Choose [1-3/S/0]: "
        local s_choice=$(read_single_char | tr '[:upper:]' '[:lower:]')
        
        case "$s_choice" in
            1) [ "$b_cfg" = "Y" ] && b_cfg="N" || b_cfg="Y" ;;
            2) [ "$b_bin" = "Y" ] && b_bin="N" || b_bin="Y" ;;
            3) [ "$b_ini" = "Y" ] && b_ini="N" || b_ini="Y" ;;
            s)
                if [ "$b_cfg" = "N" ] && [ "$b_bin" = "N" ] && [ "$b_ini" = "N" ]; then
                    printf "\n\n"
                    print_error "Nothing selected to save."
                    sleep 1
                    continue
                fi

                printf "\n\n"
                print_info "Creating Selected Backups..."
                # Atomic Save Logic
                [ "$b_cfg" = "Y" ] && [ -f "$AGH_CONFIG" ] && cp "$AGH_CONFIG" "$AGH_CONFIG.backup.$ts"
                [ "$b_bin" = "Y" ] && [ -f "/usr/bin/AdGuardHome" ] && cp "/usr/bin/AdGuardHome" "/usr/bin/AdGuardHome.backup.$ts"
                [ "$b_ini" = "Y" ] && [ -f "/etc/init.d/adguardhome" ] && cp "/etc/init.d/adguardhome" "/etc/init.d/adguardhome.backup.$ts"
                
                printf "\n"
                print_success "Backup $ts completed!"
                press_any_key
                return 0
                ;;
            0) return 1 ;;
            *) print_error "Invalid option" ; sleep 1 ;;
        esac
    done
}

manage_agh_backups() {
    local backups=$(ls /etc/AdGuardHome/config.yaml.backup.* 2>/dev/null | sed 's/.*\.backup\.//' | sort -r)
    [ -z "$backups" ] && { print_error "No backups found."; sleep 2; return; }

    clear
    print_centered_header "Pick a Backup Date"
    printf " ────────────────────────────────────────────────────────────\n"
    printf " %-3s  %-18s  %-5s  %-5s  %-5s\n" "#" "Date / Time" "Conf" "Bin" "Init"
    printf "\n"

    local i=1
    local map_file="/tmp/agh_bk_map"
    > "$map_file"

    for ts in $backups; do
        local p_date="${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:8:2}:${ts:10:2}"
        local has_bin="[N]"; [ -f "/usr/bin/AdGuardHome.backup.$ts" ] && has_bin="[Y]"
        local has_ini="[N]"; [ -f "/etc/init.d/adguardhome.backup.$ts" ] && has_ini="[Y]"

        printf " %-3s  %-18s  %-5s  %-5s  %-5s\n" "$i." "$p_date" "[Y]" "$has_bin" "$has_ini"
        printf "%s|%s\n" "$i" "$ts" >> "$map_file"
        i=$((i+1))
    done
    printf " ────────────────────────────────────────────────────────────\n"
    printf " [#] To Restore   [0] Cancel\n"
    printf " Choose [1-$((i-1))/0]: "
    read -r b_choice
    printf "\n"
    [ -z "$b_choice" ] || [ "$b_choice" = "0" ] && return

    local selected_ts=$(grep "^$b_choice|" "$map_file" | cut -d'|' -f2)
    [ -z "$selected_ts" ] && return

    local fix_cfg="Y"; local fix_bin="N"; local fix_ini="N"
    while true; do
        clear
        print_centered_header "Select items to restore from: $selected_ts"
        printf " ────────────────────────────────────────────────────────────\n"
        printf " 1. [ %s ] Configuration Settings\n" "$fix_cfg"
        printf " 2. [ %s ] App Binary (AdGuardHome)\n" "$fix_bin"
        printf " 3. [ %s ] Startup Script (init.d)\n\n" "$fix_ini"
        printf " ────────────────────────────────────────────────────────────\n"
        printf " [#] Toggle Restore   [C] Confirm   [0] Cancel\n"
        printf " Choose [1-3/C/0]: "
        local s_choice=$(read_single_char | tr '[:upper:]' '[:lower:]')
        printf "\n"
        case "$s_choice" in
            1) [ "$fix_cfg" = "Y" ] && fix_cfg="N" || fix_cfg="Y" ;;
            2) [ "$fix_bin" = "Y" ] && fix_bin="N" || fix_bin="Y" ;;
            3) [ "$fix_ini" = "Y" ] && fix_ini="N" || fix_ini="Y" ;;
            c) 
                if [ "$fix_cfg" = "N" ] && [ "$fix_bin" = "N" ] && [ "$fix_ini" = "N" ]; then
                    printf "\n"
                    print_error "Nothing selected to restore. Select an option or 0 to cancel."
                    press_any_key
                    continue
                fi
                
                printf "\nApplying Restore...\n"
                $AGH_INIT stop >/dev/null 2>&1
                [ "$fix_cfg" = "Y" ] && cp "/etc/AdGuardHome/config.yaml.backup.$selected_ts" "/etc/AdGuardHome/config.yaml"
                [ "$fix_bin" = "Y" ] && cp "/usr/bin/AdGuardHome.backup.$selected_ts" "/usr/bin/AdGuardHome"
                [ "$fix_ini" = "Y" ] && cp "/etc/init.d/adguardhome.backup.$selected_ts" "/etc/init.d/adguardhome"
                $AGH_INIT start >/dev/null 2>&1
                printf "\n"
                print_success "Restore complete!"; press_any_key; return ;;
            0) return ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

delete_agh_backups() {
    local map_file="/tmp/agh_del_map"
    [ -f "$map_file" ] && rm -f "$map_file"
    while true; do
        local backups=$(ls /etc/AdGuardHome/config.yaml.backup.* 2>/dev/null | sed 's/.*\.backup\.//' | sort -r)
        [ -z "$backups" ] && { print_error "No backups found."; sleep 2; return; }

        # Initialize map file if it doesn't exist (Index|Timestamp|Selected)
        if [ ! -f "$map_file" ]; then
            local i=1
            for ts in $backups; do
                echo "$i|$ts|0" >> "$map_file"
                i=$((i+1))
            done
        fi

        clear
        print_centered_header "AdGuardHome Backup Cleanup"
        printf " %-4s  %-4s  %-18s  %-5s  %-5s  %-5s  %-6s\n" "Sel" "Idx" "Date / Time" "Conf" "Bin" "Init" "Size"
        printf " ──────────────────────────────────────────────────────────────\n"

        while IFS='|' read -r idx ts sel; do
            local p_date="${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:8:2}:${ts:10:2}"
            local s_box="[ ]"; [ "$sel" -eq 1 ] && s_box="[✓] "
            
            # Check presence of components
            local c="[Y]"; [ ! -f "/etc/AdGuardHome/config.yaml.backup.$ts" ] && c="[N]"
            local b="[Y]"; [ ! -f "/usr/bin/AdGuardHome.backup.$ts" ] && b="[N]"
            local n="[Y]"; [ ! -f "/etc/init.d/adguardhome.backup.$ts" ] && n="[N]"

            # Calculate total size for this timestamp
            local ts_bytes=0
            for f in "/etc/AdGuardHome/config.yaml.backup.$ts" "/usr/bin/AdGuardHome.backup.$ts" "/etc/init.d/adguardhome.backup.$ts"; do
                [ -f "$f" ] && ts_bytes=$((ts_bytes + $(ls -nl "$f" | awk '{print $5}')))
            done
            
            # Convert to human readable
            local p_size="0B"
            if [ "$ts_bytes" -ge 1048576 ]; then
                p_size=$(awk "BEGIN {printf \"%.1fM\", $ts_bytes/1048576}")
            elif [ "$ts_bytes" -ge 1024 ]; then
                p_size=$(awk "BEGIN {printf \"%.1fK\", $ts_bytes/1024}")
            else
                p_size="${ts_bytes}B"
            fi

            printf " %-4s  %-4s  %-18s  %-5s  %-5s  %-5s  %-6s\n" "$s_box" "$idx." "$p_date" "$c" "$b" "$n" "$p_size"
        done < "$map_file"

        printf " ──────────────────────────────────────────────────────────────\n"
        printf " [A] All   [N] None   [T#] Toggle   [C] Confirm   [0] Cancel\n"
        printf " Enter command: "
        read -r input
        local cmd=$(echo "$input" | tr '[:upper:]' '[:lower:]')

        case "$cmd" in
            a) sed -i 's/|0$/|1/' "$map_file" ;;
            n) sed -i 's/|1$/|0/' "$map_file" ;;
            t*) 
                local t_idx="${cmd#t}"
                if grep -q "^$t_idx|" "$map_file"; then
                    local current_state=$(grep "^$t_idx|" "$map_file" | cut -d'|' -f3)
                    local new_state=$((1 - current_state))
                    sed -i "s/^$t_idx|.*|.*/$(grep "^$t_idx|" "$map_file" | cut -d'|' -f1-2)|$new_state/" "$map_file"
                fi ;;
            c)
                if ! grep -q "|1$" "$map_file"; then
                    printf "\n"
                    print_error "No backups selected."; press_any_key ; continue
                fi
                printf "\n"
                print_warning "Delete selected backups? [y/N]: "
                if [ "$(read_single_char)" = "y" ]; then
                    while IFS='|' read -r idx ts sel; do
                        if [ "$sel" -eq 1 ]; then
                            rm -f "/etc/AdGuardHome/config.yaml.backup.$ts"
                            rm -f "/usr/bin/AdGuardHome.backup.$ts"
                            rm -f "/etc/init.d/adguardhome.backup.$ts"
                        fi
                    done < "$map_file"
                    printf "\n"
                    print_success "Selected backups purged."
                    press_any_key;
                    rm -f "$map_file"
                    return
                fi ;;
            0) rm -f "$map_file"; return ;;
            *) print_error "Invalid command"; sleep 1 ;;
        esac
    done
}

sub_setup_config() {
    while true; do
        clear
        print_centered_header "AdGuardHome Setup, Access & UI Updates"
        printf "1️⃣  Filter Storage (10MB Limit)\n"
        printf "2️⃣  UI Direct Access\n"
        printf "3️⃣  UI Updates\n"
        printf "0️⃣  Back to Control Center\n"
        printf "\nChoose [1-3/0]: "
        read -r s_opt
        case "$s_opt" in
            1) manage_agh_storage ;;
            2) manage_agh_direct_access ;;
            3) manage_agh_ui_updates ;;
            0) break ;;
            *) print_error "Invalid option" ; sleep 1 ;;
        esac
    done
}

sub_backup_recovery() {
    while true; do
        get_agh_stats 
        clear
        print_centered_header "AdGuardHome Backup & Recovery Suite"
        printf " ${CYAN}OVERVIEW${RESET}\n"
        printf "   Latest: %s  ⌯  Total Files: %s\n\n" "${bk_date:-None}" "${bk_file_count:-0}"
        printf " ${CYAN}STORAGE STATUS${RESET}\n"
        printf "   Used: %s  ⌯  Free: %s\n" "${bk_total_u:-0B}" "${qlog_f:-N/A}"
        printf " ────────────────────────────────────────────────\n\n"
        printf "1️⃣  Save a New Backup\n"
        printf "2️⃣  Restore from Backup\n"
        printf "3️⃣  Manage/Delete Backups\n"
        printf "0️⃣  Back to Control Center\n"
        printf "\nChoose [1-3/0]: "
        read -r b_opt
        case "$b_opt" in
            1) create_agh_backup ;;
            2) manage_agh_backups ;;
            3) delete_agh_backups ;;
            0) break ;;
            *) print_error "Invalid option" ; sleep 1 ;;
        esac
    done
}

sub_service_health() {
    while true; do
        clear
        print_centered_header "AdGuardHome Service, Logs & Cache Purge"
        printf "1️⃣  Enable / Disable / Restart\n"
        printf "2️⃣  Watch Live Logs\n"
        printf "3️⃣  Clear Filter Cache\n"
        printf "0️⃣  Back to Control Center\n"
        printf "\nChoose [1-3/0]: "
        read -r h_opt
        case "$h_opt" in
            1) 
               if is_agh_running; then
                   printf "\n"
                   print_warning "Service is RUNNING. Toggle [D]isable, [R]estart, or [0] Cancel? "
                   local tr=$(read_single_char | tr '[:upper:]' '[:lower:]')
                   if [ "$tr" = "d" ]; then
                       uci set adguardhome.config.enabled='0' && uci commit adguardhome
                       $AGH_INIT stop >/dev/null 2>&1 && print_success "Service Disabled"
                   elif [ "$tr" = "r" ]; then
                       $AGH_INIT restart >/dev/null 2>&1 && print_success "Service Restarted"
                   fi
               else
                   printf "\n"
                   print_warning "Service is STOPPED. Enable now? [y/N]: "
                   if [ "$(read_single_char | tr '[:upper:]' '[:lower:]')" = "y" ]; then
                       uci set adguardhome.config.enabled='1' && uci commit adguardhome
                       $AGH_INIT enable >/dev/null 2>&1 && $AGH_INIT start >/dev/null 2>&1 && print_success "Service Enabled"
                   fi
               fi ; press_any_key ;;
            2) 
               # RESTORED: Your specific tested logread logic
               clear
               print_centered_header "AdGuardHome System Logs (Ctrl+C to exit)"
               sleep 1
               trap 'printf "\n\n" ; print_warning "Stopping log viewing..."' INT
               logread -l 20 -e "AdGuardHome" 2>/dev/null
               logread -f -e "AdGuardHome" 2>/dev/null
               trap - INT
               press_any_key
               ;;
            3) 
               printf "\n"
               print_warning "Clear all cached filter files? [y/N]: "
               if [ "$(read_single_char | tr '[:upper:]' '[:lower:]')" = "y" ]; then
                   local wd=$(get_agh_workdir)
                   rm -rf "${wd:-/etc/AdGuardHome}/data/filters/"*
                   $AGH_INIT restart >/dev/null 2>&1 && print_success "Filters Purged"
                   cached_rules="" 
               fi ; press_any_key ;;
            0) break ;;
            *) print_error "Invalid option" ; sleep 1 ;;
        esac
    done
}

sub_confirm_factory_reset() {
    local L_INIT="/etc/init.d/adguardhome"
    local L_BIN="/usr/bin/AdGuardHome"
    local L_CONF="/etc/AdGuardHome/config.yaml"
    local init_ok=0 bin_ok=0 conf_ok=0
    local was_running=0
    local was_uci_enabled=0

    printf "\n"
    print_warning "Restore factory system files and defaults from /rom? [y/N]: "
    local confirm=$(read_single_char | tr '[:upper:]' '[:lower:]')
    [ "$confirm" != "y" ] && return

    # --- 1. Pre-Check State & Stop Phase ---
    # Call the function directly to check the exit status
    is_agh_running && was_running=1
    
    if [ "$(uci -q get adguardhome.config.enabled)" = "1" ]; then
        was_uci_enabled=1
    fi

    if [ "$was_running" -eq 1 ]; then
        printf "\n"
        print_info "AdGuardHome is currently running. Stopping service..."
        [ -f "$L_INIT" ] && $L_INIT stop >/dev/null 2>&1
        sleep 1
        if is_agh_running; then
            kill -9 $(pidof AdGuardHome) >/dev/null 2>&1
            sleep 1
        fi
        print_success "Service stopped successfully."
    fi

    # --- 2. Restore Files from ROM ---
    [ -f "/rom$L_INIT" ] && cp "/rom$L_INIT" "$L_INIT" && chmod +x "$L_INIT" && init_ok=1
    [ -f "/rom$L_BIN" ]  && cp "/rom$L_BIN" "$L_BIN"   && chmod +x "$L_BIN"  && bin_ok=1
    [ -f "/rom$L_CONF" ] && cp "/rom$L_CONF" "$L_CONF" && conf_ok=1
    
    # --- 3. Report Status ---
    printf "\n"
    [ $init_ok -eq 1 ] && print_success "Init Script restored" || print_error "Init Script missing in ROM"
    [ $bin_ok -eq 1 ]  && print_success "Binary restored"      || print_error "Binary missing in ROM"
    [ $conf_ok -eq 1 ] && print_success "Config yaml restored" || print_error "Config missing in ROM"
    printf "\n"

    # --- 4. Finalization Logic ---
    if [ $init_ok -eq 1 ] && [ $bin_ok -eq 1 ] && [ $conf_ok -eq 1 ]; then
        # Handle administrative state (UCI)
        if [ "$was_uci_enabled" -eq 1 ]; then
            uci set adguardhome.config.enabled='1' && uci commit adguardhome
            $L_INIT enable >/dev/null 2>&1
            print_success "Full recovery successful! AdGuardHome auto-start re-enabled."
            printf "\n"
        else
            print_warning "AdGuardHome was disabled in UCI. Keep it disabled? [y/N]: "
            local keep_disabled=$(read_single_char | tr '[:upper:]' '[:lower:]')
            if [ "$keep_disabled" != "y" ]; then
                uci set adguardhome.config.enabled='1' && uci commit adguardhome
                $L_INIT enable >/dev/null 2>&1
                print_success "AdGuardHome enabled in GL-WebUI and UCI."
                was_uci_enabled=1
            fi
            printf "\n"
        fi
        
        # Handle operational state (Running)
        if [ "$was_running" -eq 1 ]; then
            print_info "Automatically restarting service..."
            $L_INIT start >/dev/null 2>&1 && print_success "Service restored to running state."
        elif [ "$was_uci_enabled" -eq 1 ]; then
            print_warning "AdGuardHome is enabled but not running. Start it now? [y/N]: "
            local start_now=$(read_single_char | tr '[:upper:]' '[:lower:]')
            if [ "$start_now" = "y" ]; then
                printf "\n"
                print_info "Starting AdGuardHome...\n"
                $L_INIT start >/dev/null 2>&1 && print_success "Service started successfully."
            fi
        fi
    elif [ $init_ok -eq 1 ] || [ $bin_ok -eq 1 ] || [ $conf_ok -eq 1 ]; then
        print_warning "Partial recovery. Some files are still missing."
    else
        print_error "Recovery failed. Files not found in /rom or write error."
    fi
    
    press_any_key
}

get_agh_stats() {
    # 1. Basic Status Icons
    run_icon="❌"; is_agh_running && run_icon="✅"
    local web_enabled=$(uci -q get adguardhome.config.enabled)
    web_icon="❌"; [ "$web_enabled" = "1" ] && web_icon="✅"
    
    # 2. Setup Paths
    local AGH_CONFIG=$(get_agh_config)
    local workdir=$(get_agh_workdir)
    local data_dir="${workdir:-/etc/AdGuardHome}/data"

    # 3. List & Rules Logic
    list_count=$(grep -c "url:" "$AGH_CONFIG" 2>/dev/null || echo "0")
    if [ -z "$cached_rules" ]; then
        local raw_val=$(find "$data_dir/filters" -type f 2>/dev/null | xargs cat 2>/dev/null | wc -l)
        cached_rules=$(printf "$raw_val" | awk '{len=length($0); for(i=len-3;i>0;i-=3) $0=substr($0,1,i) "," substr($0,i+1); print $0}')
    fi

    # 4. Storage Metric: Filters
    filt_u=$(du -sh "$data_dir/filters" 2>/dev/null | awk '{print $1}')
    filt_f=$(df -h "$data_dir/filters" 2>/dev/null | awk 'NR==2 {print $4}')

    # 5. Storage Metric: Query Logs (DBs + JSON)
    local q_bytes=0
    for f in "$data_dir/stats.db" "$data_dir/sessions.db" "$data_dir/querylog.json"; do
        [ -f "$f" ] && q_bytes=$((q_bytes + $(ls -nl "$f" | awk '{print $5}')))
    done
    qlog_u=$(awk "BEGIN {printf \"%.1fM\", ${q_bytes:-0}/1048576}")
    qlog_f=$(df -h "$data_dir" 2>/dev/null | awk 'NR==2 {print $4}')

    # 6. Backup Storage & Last Date
    local bk_locs="/etc/AdGuardHome /usr/bin /etc/init.d"
    
    local bk_bytes=$(find $bk_locs -maxdepth 1 -name "*.backup.*" -exec ls -nl {} + 2>/dev/null | awk '{sum += $5} END {print sum + 0}')
    
    bk_total_u=$(awk "BEGIN { 
        mbs = $bk_bytes / 1048576;
        if (mbs > 0 && mbs < 0.1) printf \"0.01M\";
        else printf \"%.2fM\", mbs;
    }")

    bk_file_count=$(find $bk_locs -maxdepth 1 -name "*.backup.*" 2>/dev/null | wc -l)
    
    local last_bk_file=$(ls -t /etc/AdGuardHome/config.yaml.backup.* 2>/dev/null | head -n1)
    if [ -n "$last_bk_file" ]; then
        # Extracts YYYYMMDD from the suffix
        local ts=$(echo "$last_bk_file" | awk -F'.backup.' '{print $2}')
        bk_date="${ts:0:4}-${ts:4:2}-${ts:6:2}"
    else
        bk_date="None"
    fi

    # 7. Version Info
    v_num=$(/usr/bin/AdGuardHome --version 2>/dev/null | awk '{print $4}')
}

agh_control_center() {
    while true; do
        get_agh_stats
        clear
        print_centered_header "AdGuardHome Control Center"
        printf " ${CYAN}STATUS${RESET}\n   Run: %s  ⌯  GL-WebUI: %s  ⌯  Version: v%s\n\n" "${run_icon:-❌}" "${web_icon:-❌}" "${v_num:-N/A}"
        printf " ${CYAN}FILTERS${RESET}\n   Lists: %s  ⌯  Rules: %s\n\n" "${list_count:-0}" "${cached_rules:-0}"
        printf " ${CYAN}STORAGE${RESET}\n   Filters: %s/%s  ⌯  Logs: %s/%s\n\n" "${filt_u:-0B}" "${filt_f:-N/A}" "${qlog_u:-0B}" "${qlog_f:-N/A}"
        printf " ${CYAN}BACKUP${RESET}\n   Date: %s  ⌯  Size: %s  ⌯  Files: %s\n\n" "${bk_date:-None}" "${bk_total_u:-0B}" "${bk_file_count:-0}"
        printf " ────────────────────────────────────────────────\n\n"
        printf "1️⃣  Manage Allow/Blocklists\n"
        printf "2️⃣  Setup, Access & UI Updates\n"
        printf "3️⃣  Backup & Recovery Suite\n"
        printf "4️⃣  Service, Logs & Cache Purge\n"
        printf "🆑 Reset to Factory Settings (Start Over)\n"
        printf "0️⃣  Back to Main Menu\n"
        printf "❓ Help\n"
        printf "\nChoose [1-4/CL/0/?]: "
        read -r choice

        case "$choice" in
            1) manage_agh_lists ;;
            2) sub_setup_config ;;
            3) sub_backup_recovery ;;
            4) sub_service_health ;;
            [cC][lL]) sub_confirm_factory_reset ;;
            0) break ;;
            \?|h|H|❓) show_agh_help ;;
            *) print_error "Invalid option" ; sleep 1 ;;
        esac
    done
}

# -----------------------------
# Zram Swap Management
# -----------------------------
show_zram_help() {
    clear
    print_centered_header "Zram Swap - Help"
    
    cat << 'HELPEOF'
Zram Swap – Quick Help

What is zram swap?
──────────────────
Zram creates a compressed block device in your router's RAM and uses it as swap space. 
Instead of writing swap data to slow flash storage (which wears it out quickly), zram 
compresses the data and keeps it in RAM. This is much faster and protects your NAND/eMMC.

Main benefits on GL.iNet routers:
• Greatly improves performance when RAM is low (e.g. heavy VPN, AdGuardHome, many clients)
• Reduces lag and stuttering under memory pressure
• Significantly extends the lifespan of your router's flash storage
• Uses very little CPU overhead on modern router SoCs

Typical recommendations:
• 25–50% of total RAM is a good starting size (e.g. 128–256 MB on a 512 MB router)
• Most GL.iNet users enable it if they run AdGuardHome + VPN or have ≥10–15 devices connected

When should you use it?
Yes → if your router frequently runs out of RAM or you notice slowdowns
No  → if you have 1 GB+ RAM and very light usage

Important notes:
• Zram uses some CPU to compress/decompress → not ideal on very old/slow CPUs
• Data in zram is lost on reboot (normal for swap)
• Routers with 512MiB flash or less will have a forced limit for AdGuardHome allow/block lists.
  See Option 3 - Manage AdGuardHome Storage

In this menu you can:
1. Install & enable zram swap
2. Disable it (stops and disables on boot)
3. Completely uninstall the package
HELPEOF
    
    press_any_key
}

manage_zram() {
    while true; do
        clear
        print_centered_header "Zram Swap Management"
        
        printf " %b\n" "${CYAN}STATUS${RESET}"
        if command -v zram >/dev/null 2>&1 || [ -f /etc/init.d/zram ]; then
            if /etc/init.d/zram enabled 2>/dev/null; then
                printf "   Zram Swap: %bENABLED%b\n" "${GREEN}" "${RESET}"
                
                if [ -f /sys/block/zram0/disksize ]; then
                    disksize=$(cat /sys/block/zram0/disksize 2>/dev/null)
                    disksize_mb=$((disksize / 1024 / 1024))
                    printf "   Disk Size: %d MB\n" "$disksize_mb"
                fi
                
                if swapon -s 2>/dev/null | grep -q zram; then
                    printf "   Status: %bACTIVE%b\n" "${GREEN}" "${RESET}"
                else
                    printf "   Status: %bINACTIVE%b\n" "${YELLOW}" "${RESET}"
                fi
            else
                printf "   Zram Swap: %bDISABLED%b\n" "${YELLOW}" "${RESET}"
            fi
        else
            printf "   Zram Swap: %bNOT INSTALLED%b\n" "${RED}" "${RESET}"
        fi
        
        printf "\n1️⃣  Install and Enable\n"
        printf "2️⃣  Disable\n"
        printf "3️⃣  Uninstall Package\n"
        printf "0️⃣  Main menu\n"
        printf "❓ Help\n"
        printf "\nChoose [1-3/0/?]: "
        read -r zram_choice
        printf "\n"
        
        case $zram_choice in
            1)
                if ! opkg list-installed | grep -q "^zram-swap"; then
                    print_warning "zram-swap not installed, installing..."
                    if [ "$opkg_updated" -eq 0 ]; then
                        printf "Updating package lists...\n"
                        opkg update >/dev/null 2>&1
                        opkg_updated=1
                    fi
                    opkg install zram-swap >/dev/null 2>&1
                    if opkg list-installed | grep -q "^zram-swap"; then
                        print_success "zram-swap package installed"
                    else
                        print_error "Failed to install zram-swap"
                        press_any_key
                        continue
                    fi
                fi
                
                if [ -f /etc/init.d/zram ]; then
                    /etc/init.d/zram enable >/dev/null 2>&1
                    /etc/init.d/zram start >/dev/null 2>&1
                    print_success "Zram swap enabled and started"
                    
                    sleep 2
                    if swapon -s 2>/dev/null | grep -q zram; then
                        print_success "Zram swap is working correctly"
                    else
                        print_warning "Zram swap may not be working properly"
                    fi
                else
                    print_error "Zram init script not found"
                fi
                press_any_key
                ;;
            2)
                if [ -f /etc/init.d/zram ]; then
                    /etc/init.d/zram stop >/dev/null 2>&1
                    /etc/init.d/zram disable >/dev/null 2>&1
                    print_success "Zram swap disabled and stopped"
                else
                    print_warning "Zram swap is not installed"
                fi
                press_any_key
                ;;
            3)
                if opkg list-installed | grep -q "^zram-swap"; then
                    printf "%b" "${YELLOW}Remove zram-swap package? [y/N]: ${RESET}"
                    read -r confirm
                    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                        [ -f /etc/init.d/zram ] && /etc/init.d/zram stop >/dev/null 2>&1
                        opkg remove zram-swap >/dev/null 2>&1
                        print_success "zram-swap package removed"
                    else
                        printf "Removal cancelled.\n"
                    fi
                else
                    print_warning "zram-swap package is not installed"
                fi
                press_any_key
                ;;
            \?|h|H|❓)
                show_zram_help
                ;;
            m|M|0)
                return
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# -----------------------------
# CPU & Disk Benchmarks
# -----------------------------
benchmark_system() {
    while true; do
        clear
        print_centered_header "System Benchmarks"
        printf "1️⃣  CPU Stress Test\n"
        printf "2️⃣  CPU Benchmark (OpenSSL)\n"
        printf "3️⃣  Disk I/O Benchmark\n"
        printf "0️⃣  Main menu\n"
        printf "\nChoose [1-4/0]: "
        read -r bench_choice
        printf "\n"
        
        case $bench_choice in
            1)
                if ! command -v stress >/dev/null 2>&1; then
                    print_warning "stress not found, installing..."
                    if [ "$opkg_updated" -eq 0 ]; then
                        opkg update >/dev/null 2>&1
                        opkg_updated=1
                    fi
                    opkg install stress >/dev/null 2>&1
                    if ! command -v stress >/dev/null 2>&1; then
                        print_error "Failed to install stress"
                        press_any_key
                        continue
                    fi
                fi
                
                cpu_cores=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null)
                [ -z "$cpu_cores" ] && cpu_cores=1
                
                printf "\nHow many seconds to run stress test? [default: 60]: "
                read -r duration
                [ -z "$duration" ] && duration=60
                
                case "$duration" in
                    ''|*[!0-9]*) duration=60 ;;
                esac
                
                printf "\n%b\n" "${YELLOW}⏳ Running stress test on $cpu_cores cores for $duration seconds...${RESET}"
                printf "%b\n\n" "${YELLOW}💡 Monitor with 'top' in another session${RESET}"
                
                stress --cpu "$cpu_cores" --timeout "${duration}s" --verbose
                
                printf "\n"
                print_success "Stress test completed"
                press_any_key
                ;;
            2)
                if ! command -v openssl >/dev/null 2>&1; then
                    print_error "OpenSSL not found"
                    press_any_key
                    continue
                fi
                
                printf "\n%b\n" "${CYAN}🔧 Running OpenSSL speed benchmark...${RESET}"
                printf "%b\n\n" "${YELLOW}⏳ This will take a minute...${RESET}"
                
                printf "%b\n" "${CYAN}Single-threaded AES-256-GCM:${RESET}"
                openssl speed -elapsed -evp aes-256-gcm 2>&1 | tail -3
                
                printf "\n%b\n" "${CYAN}Single-threaded SHA256:${RESET}"
                openssl speed -elapsed sha256 2>&1 | tail -3
                
                printf "\n%b\n" "${CYAN}RSA 2048-bit signing:${RESET}"
                openssl speed -elapsed rsa2048 2>&1 | tail -5
                
                printf "\n"
                print_success "Benchmark completed"
                press_any_key
                ;;
            3)
                printf "%b\n" "${CYAN}🔧 Disk I/O Benchmark${RESET}\n"
                
                available_kb=$(df -k . | awk 'NR==2 {print $4}')
                
                test_size=0
                test_name=""
                if [ "$available_kb" -ge $((1000 * 1024)) ]; then
                    test_size=1000
                    test_name="1GB"
                elif [ "$available_kb" -ge $((500 * 1024)) ]; then
                    test_size=500
                    test_name="500MB"
                elif [ "$available_kb" -ge $((250 * 1024)) ]; then
                    test_size=250
                    test_name="250MB"
                elif [ "$available_kb" -ge $((125 * 1024)) ]; then
                    test_size=125
                    test_name="125MB"
                elif [ "$available_kb" -ge $((62 * 1024)) ]; then
                    test_size=62
                    test_name="62MB"
                elif [ "$available_kb" -ge $((31 * 1024)) ]; then
                    test_size=31
                    test_name="31MB"
                else
                    print_error "Not enough disk space (need at least 31MB)"
                    printf "Available: %d MB\n" $((available_kb / 1024))
                    press_any_key
                    continue
                fi
                
                printf "Test size: %b%s%b\n" "${GREEN}" "$test_name" "${RESET}"
                print_success "Sufficient disk space available"
                
                printf "\n%b\n" "${YELLOW}⏳ Running write test ($test_name)...${RESET}"
                sync
                write_start=$(date +%s)
                dd if=/dev/zero of=./testfile bs=1M count=$test_size conv=fsync 2>&1 | tail -3
                write_end=$(date +%s)
                write_time=$((write_end - write_start))
                [ "$write_time" -eq 0 ] && write_time=1
                
                if [ -f ./testfile ]; then
                    write_speed=$((test_size / write_time))
                    printf "%b\n" "${GREEN}✅ Write speed: ~${write_speed} MB/s${RESET}"
                fi
                
                printf "\n%b\n" "${YELLOW}⏳ Running read test ($test_name)...${RESET}"
                sync
                echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
                read_start=$(date +%s)
                dd if=./testfile of=/dev/null bs=1M 2>&1 | tail -3
                read_end=$(date +%s)
                read_time=$((read_end - read_start))
                [ "$read_time" -eq 0 ] && read_time=1
                
                read_speed=$((test_size / read_time))
                printf "%b\n" "${GREEN}✅ Read speed: ~${read_speed} MB/s${RESET}"
                
                rm -f ./testfile
                printf "\n"
                print_success "Disk benchmark completed"
                press_any_key
                ;;
            m|M|0)
                return
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# -----------------------------
# UCI Configuration Viewer
# -----------------------------
view_uci_config() {
    while true; do
        clear
        print_centered_header "System Configuration Viewer"
        printf "1️⃣  Wireless Networks\n"
        printf "2️⃣  Network Configuration\n"
        printf "3️⃣  VPN Configuration\n"
        printf "4️⃣  System Settings\n"
        printf "5️⃣  Cloud Services\n"
        printf "0️⃣  Main menu\n"
        printf "\nChoose [1-5/0]: "
        read -r config_choice
        printf "\n"
        
        case $config_choice in
            1)
                clear
                print_centered_header "Wireless Networks"
                
                all_ifaces=""
                for iface in $(uci show wireless 2>/dev/null | grep "wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1 | sort -u); do
                    ssid=$(uci get wireless.${iface}.ssid 2>/dev/null)
                    [ -n "$ssid" ] && all_ifaces="$all_ifaces $iface"
                done
                
                mlo_ifaces=""
                five_ifaces=""
                two_ifaces=""
                
                for iface in $all_ifaces; do
                    device=$(uci get wireless.${iface}.device 2>/dev/null)
                    band=$(uci get wireless.${device}.band 2>/dev/null)
                    
                    if uci get wireless.${iface}.mlo 2>/dev/null | grep -q "1"; then
                        mlo_ifaces="$mlo_ifaces $iface"
                    elif [ "$band" = "5g" ] || [ "$band" = "6g" ]; then
                        five_ifaces="$five_ifaces $iface"
                    elif [ "$band" = "2g" ]; then
                        two_ifaces="$two_ifaces $iface"
                    else
                        two_ifaces="$two_ifaces $iface"
                    fi
                done
                
                count=0
                for iface in $mlo_ifaces $five_ifaces $two_ifaces; do

                    if [ $((count % 2)) -eq 0 ] && [ $count -gt 0 ]; then
                       press_any_key
                       clear
                       print_centered_header "Wireless Networks"
                    fi
                    
                    ssid=$(uci get wireless.${iface}.ssid 2>/dev/null)
                    key=$(uci get wireless.${iface}.key 2>/dev/null)
                    encryption=$(uci get wireless.${iface}.encryption 2>/dev/null)
                    disabled=$(uci get wireless.${iface}.disabled 2>/dev/null)
                    hidden=$(uci get wireless.${iface}.hidden 2>/dev/null)
                    device=$(uci get wireless.${iface}.device 2>/dev/null)
                    mode=$(uci get wireless.${iface}.mode 2>/dev/null)
                    
                    band=$(uci get wireless.${device}.band 2>/dev/null)
                    htmode=$(uci get wireless.${device}.htmode 2>/dev/null)
                    channel=$(uci get wireless.${device}.channel 2>/dev/null)
                    
                    case "$band" in
                        2g) band_name="2.4GHz" ;;
                        5g) band_name="5GHz" ;;
                        6g) band_name="6GHz" ;;
                        *) band_name="Unknown" ;;
                    esac
                    
                    if uci get wireless.${iface}.mlo 2>/dev/null | grep -q "1"; then
                        band_name="MLO (Multi-Link)"
                    fi
                    
                    printf "%b\n" "${CYAN}Interface: $iface ($band_name)${RESET}"
                    printf "  SSID: %b%s%b\n" "${GREEN}" "$ssid" "${RESET}"
                    [ -n "$key" ] && printf "  Password: %b%s%b\n" "${YELLOW}" "$key" "${RESET}"
                    [ -n "$encryption" ] && printf "  Encryption: %s\n" "$encryption"
                    
                    if [ "$hidden" = "1" ]; then
                        printf "  Visibility: %bHidden%b\n" "${YELLOW}" "${RESET}"
                    else
                        printf "  Visibility: %bVisible%b\n" "${GREEN}" "${RESET}"
                    fi
                    
                    [ -n "$mode" ] && printf "  Mode: %s\n" "$mode"
                    [ -n "$htmode" ] && printf "  Bandwidth: %s\n" "$htmode"
                    [ -n "$channel" ] && printf "  Channel: %s\n" "$channel"
                    
                    if [ "$disabled" = "1" ]; then
                        printf "  Status: %bDisabled%b\n" "${RED}" "${RESET}"
                    else
                        printf "  Status: %bEnabled%b\n" "${GREEN}" "${RESET}"
                    fi
                    printf "\n"
                    count=$((count + 1))
                done
                
                press_any_key
                ;;
            2)
                clear
                print_centered_header "Network Configuration"
                
                printf "%b\n" "${CYAN}WAN Configuration:${RESET}"
                wan_proto=$(uci get network.wan.proto 2>/dev/null)
                wan_ipaddr=$(uci get network.wan.ipaddr 2>/dev/null)
                wan_netmask=$(uci get network.wan.netmask 2>/dev/null)
                wan_gateway=$(uci get network.wan.gateway 2>/dev/null)
                wan_dns=$(uci get network.wan.dns 2>/dev/null)
                
                [ -n "$wan_proto" ] && printf "  Protocol: %s\n" "$wan_proto"
                [ -n "$wan_ipaddr" ] && printf "  IP Address: %b%s%b\n" "${GREEN}" "$wan_ipaddr" "${RESET}"
                [ -n "$wan_netmask" ] && printf "  Netmask: %s\n" "$wan_netmask"
                [ -n "$wan_gateway" ] && printf "  Gateway: %s\n" "$wan_gateway"
                [ -n "$wan_dns" ] && printf "  DNS: %s\n" "$wan_dns"
                
                printf "\n%b\n" "${CYAN}LAN Configuration:${RESET}"
                lan_ipaddr=$(uci get network.lan.ipaddr 2>/dev/null)
                lan_netmask=$(uci get network.lan.netmask 2>/dev/null)
                lan_proto=$(uci get network.lan.proto 2>/dev/null)
                
                [ -n "$lan_proto" ] && printf "  Protocol: %s\n" "$lan_proto"
                [ -n "$lan_ipaddr" ] && printf "  IP Address: %b%s%b\n" "${GREEN}" "$lan_ipaddr" "${RESET}"
                [ -n "$lan_netmask" ] && printf "  Netmask: %s\n" "$lan_netmask"
                
                printf "\n%b\n" "${CYAN}DHCP Server:${RESET}"
                dhcp_start=$(uci get dhcp.lan.start 2>/dev/null)
                dhcp_limit=$(uci get dhcp.lan.limit 2>/dev/null)
                dhcp_leasetime=$(uci get dhcp.lan.leasetime 2>/dev/null)
                
                [ -n "$dhcp_start" ] && printf "  Start: %s\n" "$dhcp_start"
                [ -n "$dhcp_limit" ] && printf "  Limit: %s\n" "$dhcp_limit"
                [ -n "$dhcp_leasetime" ] && printf "  Lease Time: %s\n" "$dhcp_leasetime"
                printf "\n"
                
                press_any_key
                ;;
            3)
                clear
                print_centered_header "VPN Configuration"
                
                found_vpn=0
                
                if uci show network 2>/dev/null | grep -q "proto='wireguard'"; then
                    printf "%b\n" "${CYAN}WireGuard Servers:${RESET}"
                    for iface in $(uci show network | grep "proto='wireguard'" | cut -d'.' -f2 | cut -d'=' -f1); do
                        private_key=$(uci get network.${iface}.private_key 2>/dev/null)
                        listen_port=$(uci get network.${iface}.listen_port 2>/dev/null)
                        addresses=$(uci get network.${iface}.addresses 2>/dev/null)
                        
                        printf "  Interface: %b%s%b\n" "${GREEN}" "$iface" "${RESET}"
                        [ -n "$listen_port" ] && printf "    Listen Port: %s\n" "$listen_port"
                        [ -n "$addresses" ] && printf "    Addresses: %s\n" "$addresses"
                        [ -n "$private_key" ] && printf "    Private Key: %b[configured]%b\n" "${YELLOW}" "${RESET}"
                        printf "\n"
                        found_vpn=1
                    done
                fi
                
                if uci show wireguard 2>/dev/null | grep -q "=peers"; then
                    printf "%b\n" "${CYAN}WireGuard Clients:${RESET}"
                    for peer in $(uci show wireguard 2>/dev/null | grep "=peers" | cut -d'.' -f2 | cut -d'=' -f1); do
                        name=$(uci get wireguard.${peer}.name 2>/dev/null)
                        endpoint=$(uci get wireguard.${peer}.end_point 2>/dev/null)
                        addr_v4=$(uci get wireguard.${peer}.address_v4 2>/dev/null)
                        allowed=$(uci get wireguard.${peer}.allowed_ips 2>/dev/null)
                        keepalive=$(uci get wireguard.${peer}.persistent_keepalive 2>/dev/null)
                        
                        printf "  Peer: %b%s%b\n" "${GREEN}" "${name:-$peer}" "${RESET}"
                        [ -n "$endpoint" ] && printf "    Endpoint: %s\n" "$endpoint"
                        [ -n "$addr_v4" ] && printf "    Address: %s\n" "$addr_v4"
                        [ -n "$allowed" ] && printf "    Allowed IPs: %s\n" "$allowed"
                        [ -n "$keepalive" ] && printf "    Keepalive: %s sec\n" "$keepalive"
                        printf "\n"
                        found_vpn=1
                    done
                fi
                
                if [ -f /etc/config/openvpn ] && uci show openvpn 2>/dev/null | grep -q "enabled='1'"; then
                    printf "%b\n" "${CYAN}OpenVPN Instances:${RESET}"
                    for instance in $(uci show openvpn | grep "enabled='1'" | cut -d'.' -f2 | cut -d'=' -f1); do
                        config=$(uci get openvpn.${instance}.config 2>/dev/null)
                        proto=$(uci get openvpn.${instance}.proto 2>/dev/null)
                        port=$(uci get openvpn.${instance}.port 2>/dev/null)
                        
                        printf "  Instance: %b%s%b\n" "${GREEN}" "$instance" "${RESET}"
                        [ -n "$config" ] && printf "    Config: %s\n" "$config"
                        [ -n "$proto" ] && printf "    Protocol: %s\n" "$proto"
                        [ -n "$port" ] && printf "    Port: %s\n" "$port"
                        printf "\n"
                        found_vpn=1
                    done
                fi
                
                if [ "$found_vpn" -eq 0 ]; then
                    print_warning "No active VPN configurations found"
                    printf "\n"
                fi
                
                press_any_key
                ;;
            4)
                clear
                print_centered_header "System Settings"
                
                printf "%b\n" "${CYAN}System Information:${RESET}"
                hostname=$(uci get system.@system[0].hostname 2>/dev/null)
                timezone=$(uci get system.@system[0].timezone 2>/dev/null)
                zonename=$(uci get system.@system[0].zonename 2>/dev/null)
                
                [ -n "$hostname" ] && printf "  Hostname: %b%s%b\n" "${GREEN}" "$hostname" "${RESET}"
                [ -n "$zonename" ] && printf "  Timezone: %s\n" "$zonename"
                [ -n "$timezone" ] && printf "  TZ String: %s\n" "$timezone"
                
                printf "\n%b\n" "${CYAN}Root Access:${RESET}"
                if grep -q "^root:[^\*!]" /etc/shadow 2>/dev/null; then
                    printf "  Root Password: %b%s%b\n" "${GREEN}" "Set" "${RESET}"
                else
                    printf "  Root Password: %b%s%b\n" "${RED}" "Not Set" "${RESET}"
                fi
                
                ssh_port=$(uci get dropbear.@dropbear[0].Port 2>/dev/null)
                ssh_interface=$(uci get dropbear.@dropbear[0].Interface 2>/dev/null)
                ssh_pass=$(uci get dropbear.@dropbear[0].PasswordAuth 2>/dev/null)
                ssh_root=$(uci get dropbear.@dropbear[0].RootPasswordAuth 2>/dev/null)
                
                printf "\n%b\n" "${CYAN}SSH Configuration:${RESET}"
                [ -n "$ssh_port" ] && printf "  Port: %s\n" "$ssh_port" || printf "  Port: 22 (default)\n"
                [ -n "$ssh_interface" ] && printf "  Interface: %s\n" "$ssh_interface"
                
                if [ "$ssh_pass" = "0" ]; then
                    printf "  Password Auth: %b%s%b\n" "${RED}" "Disabled" "${RESET}"
                else
                    printf "  Password Auth: %b%s%b\n" "${GREEN}" "Enabled" "${RESET}"
                fi
                
                if [ "$ssh_root" = "0" ]; then
                    printf "  Root Login: %b%s%b\n" "${RED}" "Disabled" "${RESET}"
                else
                    printf "  Root Login: %b%s%b\n" "${GREEN}" "Enabled" "${RESET}"
                fi
                printf "\n"
                
                press_any_key
                ;;
            5)
                clear
                print_centered_header "Cloud Services"
                
                printf "%b\n" "${CYAN}GoodCloud:${RESET}"
                if [ -f /etc/config/gl-cloud ]; then
                    gc_enable=$(uci get gl-cloud.@cloud[0].enable 2>/dev/null)
                    gc_deviceid=$(uci get gl-cloud.@cloud[0].token 2>/dev/null)
                    gc_server=$(uci get gl-cloud.@cloud[0].server 2>/dev/null)
                    gc_email=$(uci get gl-cloud.@cloud[0].email 2>/dev/null)
                    
                    if [ "$gc_enable" = "1" ]; then
                        printf "  Status: %bENABLED%b\n" "${GREEN}" "${RESET}"
                    else
                        printf "  Status: %bDISABLED%b\n" "${RED}" "${RESET}"
                    fi
                    
                    [ -n "$gc_email" ] && printf "  Account: %b%s%b\n" "${GREEN}" "$gc_email" "${RESET}"
                    [ -n "$gc_server" ] && printf "  Server: %s\n" "$gc_server"
                    if [ -n "$gc_deviceid" ]; then
                        token_short=$(printf "%s" "$gc_deviceid" | cut -c1-16)
                        printf "  Token: %s\n" "${token_short}..."
                    fi
                else
                    print_warning "GoodCloud not configured"
                fi
                
                printf "\n%b\n" "${CYAN}AstroWarp:${RESET}"
                if ip link show mptun0 >/dev/null 2>&1 && ip -4 addr show mptun0 | grep -q 'inet '; then
                    printf "  Status: %bACTIVE%b\n" "${GREEN}" "${RESET}"
                    mptun_ip=$(ip -4 addr show mptun0 | grep 'inet ' | awk '{print $2}')
                    [ -n "$mptun_ip" ] && printf "  Interface: mptun0 (%s)\n" "$mptun_ip"
                else
                    printf "  Status: %bNOT ACTIVE%b\n" "${RED}" "${RESET}"
                    printf "  (No mptun0 interface or no IP assigned)\n"
                fi
                
                printf "\n"
                press_any_key
                ;;
            m|M|0)
                return
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# -----------------------------
# Check for updates on start
# -----------------------------
command -v clear >/dev/null 2>&1 && clear
printf "%b\n" "$SPLASH"
check_self_update "$@"

# -----------------------------
# Service Verification
# -----------------------------

if [ ! -f "$AGH_INIT" ]; then
    clear
    printf "%b\n" "$SPLASH"
    print_error "AdGuardHome startup script missing! Will attempt AGH factory reset to restore it."
    sub_confirm_factory_reset
    
    # Second check: If still missing after the user had a chance to fix it
    if [ ! -f "$AGH_INIT" ]; then
        AGH_DISABLED=1
        print_warning "Recovery failed. AdGuardHome features will be disabled.\n"
        sleep 2
    fi
fi


# -----------------------------
# Main Menu
# -----------------------------
show_menu() {
    while true; do
        clear
        printf "%b\n" "$SPLASH"
        printf "%b\n" "${CYAN}Please select an option:${RESET}\n"
        printf "1️⃣  Show Hardware Information\n"
        printf "2️⃣  AdGuardHome Control Center\n"
        printf "3️⃣  Manage Zram Swap\n"
        printf "4️⃣  System Benchmarks (CPU & Disk)\n"
        printf "5️⃣  View System Configuration (UCI)\n"
        printf "6️⃣  Check for Update\n"
        printf "0️⃣  Exit\n"
        printf "\nChoose [1-6/0]: "
        read opt
        
        case $opt in
            1) show_hardware_info ;;
            2) [ $AGH_DISABLED != 1 ] && agh_control_center || { print_error "AGH not found. Feature disabled."; sleep 2; } ;;
            3) manage_zram ;;
            4) benchmark_system ;;
            5) view_uci_config ;;
            6) check_self_update "$@"; press_any_key ;;
            0) clear; printf "\n%b\n\n" "${GREEN}✅ Thanks for using GL.iNet Toolkit!${RESET}"; exit 0 ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# -----------------------------
# Start
# -----------------------------
show_menu
