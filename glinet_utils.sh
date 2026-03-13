#!/bin/sh
# GL.iNet Router Toolkit
# Author: phantasm22
# License: GPL-3.0
# Version: 2026-03-12
#
# This script provides system utilities for GL.iNet routers including:
# - Hardware information display with pagination
# - AdGuardHome management (UI updates, storage limits, lists)
# - System tweaks (zram, SSH keys, package management)
# - Benchmarking tools (network speed tests, CPU stress test)
# - System configuration viewer
# - Self-update mechanism to fetch latest script from GitHub
# - User-friendly interface with color coding and emojis
# - Robust error handling and input validation
# - Designed for OpenWrt-based GL.iNet routers, tested on various models
# Note: Some features may require specific hardware capabilities or firmware versions.

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
opkg_updated=0

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
check_opkg_updated() {
    if [ "$opkg_updated" -eq 0 ]; then
        print_info "Updating package lists...\n"
        opkg update >/dev/null 2>&1
        opkg_updated=1
    fi
}

get_free_space() {
        local path="$1"
        while [ -n "$path" ] && [ ! -d "$path" ]; do
            path="${path%/*}"
        done
        [ -z "$path" ] && path="/"
        df -Ph "$path" 2>/dev/null | awk 'NR==2 {print $4}'
    }

get_fan_speed() {
    local fan_val=""
    local gl_path="/proc/gl-hw-info/fan"
    local node=""
    if [ -f "$gl_path" ]; then
        read -r node rest < "$gl_path" 2>/dev/null
        if [ -n "$node" ]; then
            for f in /sys/class/hwmon/"$node"/fan*_input; do
                if [ -f "$f" ]; then
                    read -r fan_val < "$f" 2>/dev/null
                    break
                fi
            done
        fi
    fi
    if [ -z "$fan_val" ]; then
        for f in /sys/class/hwmon/hwmon*/fan*_input; do
            if [ -f "$f" ]; then
                read -r fan_val < "$f" 2>/dev/null
                break
            fi
        done
    fi
    echo "${fan_val:-N/A}"
}

get_cpu_temp() {
    local raw_temp=""
    local temp_path=""
    if [ -f /proc/gl-hw-info/temperature ]; then
        read -r temp_path < /proc/gl-hw-info/temperature 2>/dev/null
    fi
    if [ -f "$temp_path" ]; then
        read -r raw_temp < "$temp_path" 2>/dev/null
    fi
    if [ -z "$raw_temp" ]; then
        for f in /sys/class/hwmon/hwmon*/temp*_input; do
            if [ -f "$f" ]; then
                read -r raw_temp < "$f" 2>/dev/null
                break
            fi
        done
    fi
    if [ -n "$raw_temp" ] && [ "$raw_temp" -ge 1000 ]; then
        local whole=$((raw_temp / 1000))
        local decimal=$(( (raw_temp % 1000) / 10 ))
        local formatted_decimal=$(printf "%02d" "$decimal")
        echo "$whole.$formatted_decimal"
    else
        echo "unknown"
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

get_mem_stats() {
    local t=0 a=0 f=0
    if [ -f /proc/meminfo ]; then
        while read -r label value unit; do
            case "$label" in
                MemTotal:)     t=$((value / 1024)) ;;
                MemAvailable:) a=$((value / 1024)) ;;
                MemFree:)      f=$((value / 1024)) ;;
            esac
            [ "$t" -gt 0 ] && [ "$a" -gt 0 ] && [ "$f" -gt 0 ] && break
        done < /proc/meminfo
    fi
    local m=$t
    if [ "$m" -le 32 ]; then mem_rounded=32
    elif [ "$m" -le 64 ]; then mem_rounded=64
    elif [ "$m" -le 128 ]; then mem_rounded=128
    elif [ "$m" -le 256 ]; then mem_rounded=256
    elif [ "$m" -le 512 ]; then mem_rounded=512
    elif [ "$m" -le 1024 ]; then mem_rounded=1024
    elif [ "$m" -le 2048 ]; then mem_rounded=2048
    elif [ "$m" -lt 3072 ]; then mem_rounded=3072
    elif [ "$m" -le 4096 ]; then mem_rounded=4096
    else mem_rounded=$(( (m + 128) / 256 * 256 ))
    fi
    mem_total=$t
    mem_avail=$a
    mem_free=$f
    mem_used=$((t - a))
    local p_scaled=0
    if [ "$t" -gt 0 ]; then
        p_scaled=$(( (mem_used * 1000) / t ))
    fi
    mem_p_whole=$((p_scaled / 10))
    mem_p_decimal=$((p_scaled % 10))
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
    if ! pidof AdGuardHome >/dev/null 2>&1; then
        return 1
    fi

    if netstat -tunlp | grep -q "AdGuardHome"; then
        return 0
    fi

    return 1
}

# -----------------------------
# Hardware Information Display
# -----------------------------
show_hardware_info() {
    page=1
    total_pages=4
    nav_choice=""
    
    clear
    
    if ! command -v lscpu >/dev/null 2>&1; then
        print_centered_header "Hardware Information"
        check_opkg_updated
        print_info "Installing lscpu for enhanced CPU information...\n"
        opkg install lscpu >/dev/null 2>&1
        clear
    fi

    if command -v uci >/dev/null 2>&1; then
        hostname=$(uci get system.@system[0].hostname 2>/dev/null)
    fi

    if [ -f /proc/gl-hw-info/device_mac ]; then
        mac=$(cat /proc/gl-hw-info/device_mac 2>/dev/null)
    fi

    if [ -f /proc/gl-hw-info/device_sn ]; then
        sn=$(cat /proc/gl-hw-info/device_sn 2>/dev/null)
    fi

    if [ -f /proc/gl-hw-info/device_ddns ]; then
        ddns=$(cat /proc/gl-hw-info/device_ddns 2>/dev/null)
    fi

    cpu_vendor_model=$(get_cpu_vendor_model)

    if command -v lscpu >/dev/null 2>&1; then
        cpu_cores=$(lscpu 2>/dev/null | grep "^CPU(s):" | awk '{print $2}')
        cpu_freq=$(lscpu 2>/dev/null | grep "CPU max MHz" | awk '{print $4}')
        [ -z "$cpu_freq" ] && cpu_freq=$(lscpu 2>/dev/null | grep "CPU MHz" | awk '{print $3}')
    else
        cpu_cores=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null)
    fi

    if [ -z "$cpu_freq" ]; then
        case "$cpu_vendor_model" in
            *MT7981*) cpu_freq="1300" ;; # Beryl AX
            *MT7986*) cpu_freq="2000" ;; # Flint 2
        esac
    fi

    # 1. Primary: GL.iNet Universal Hardware Info (4.x+ Firmware)
    if [ -f /proc/gl-hw-info/flash_size ]; then
        flash_raw=$(cat /proc/gl-hw-info/flash_size | sed 's/MiB/MB/')
        
        # Determine type: eMMC is usually > 1GB or specifically on Brume/Flint series
        # But we can be precise by checking for the block device existence
        if [ -b /dev/mmcblk0 ]; then
            type="eMMC"
        else
            type="NAND Flash"
        fi
        storage_info=$(printf "   Physical %s: %b%s%b\n" "$type" "${GREEN}" "$flash_raw" "${RESET}")
    
    # 2. Smart dmesg detection
    elif dmesg | grep -iE "nand|spi|mtd|mmc" | grep -iq "MiB"; then
        d_line=$(dmesg | grep -iE "nand|spi|mtd|mmc" | grep -i "MiB" | head -n 1)
        d_size=$(echo "$d_line" | grep -oE '[0-9]+ MiB' | sed 's/MiB/MB/')
        
        case "$(echo "$d_line" | tr '[:upper:]' '[:lower:]')" in
            *nand*) type="NAND Flash" ;;
            *spi*)  type="SPI Flash" ;;
            *mmc*)  type="eMMC" ;;
            *)      type="Flash Storage" ;;
        esac
        storage_info=$(printf "   Physical %s: %b%s%b\n" "$type" "${GREEN}" "$d_size" "${RESET}")
    
    # 3. Check for eMMC
    elif [ -b /dev/mmcblk0 ]; then
        mmc_blocks=$(cat /sys/block/mmcblk0/size)
        # Convert 512-byte blocks to MB
        mmc_mb=$((mmc_blocks * 512 / 1024 / 1024))
        
        if [ "$mmc_mb" -ge 1000 ]; then
            mmc_gb=$(( (mmc_mb + 512) / 1024 ))
            storage_info=$(printf "   Physical eMMC: %b%d GB%b\n" "${GREEN}" "$mmc_gb" "${RESET}")
        else
            storage_info=$(printf "   Physical eMMC: %b%d MB%b\n" "${GREEN}" "$mmc_mb" "${RESET}")
        fi

    # 4. Fallback to MTD 
    elif [ -f /proc/mtd ]; then
        max_hex=$(awk 'NR>1 {print $2}' /proc/mtd | sort -r | head -n 1)
        
        if [ -n "$max_hex" ]; then
            # Convert Hex to Decimal bytes using shell printf
            flash_bytes=$(printf "%d" "0x$max_hex")
            flash_mb=$((flash_bytes / 1024 / 1024))
            
            if [ "$flash_mb" -ge 1000 ]; then
                flash_gb=$(( (flash_mb + 512) / 1024 ))
                storage_info=$(printf "   Physical NAND: %b%d GB%b\n" "${GREEN}" "$flash_gb" "${RESET}")
            else
                storage_info=$(printf "   Physical NAND: %b%d MB%b\n" "${GREEN}" "$flash_mb" "${RESET}")
            fi
        fi
    else
        storage_info=$(printf "   Physical Storage: %bUnknown%b\n" "${RED}" "${RESET}")
    fi

    refresh_counter=0

    while true; do
        if [ "$page" -eq 1 ]; then 
            printf '\033[H\033[J'
            printf '\033[?25l'
            if [ $((refresh_counter % 10)) -eq 0 ]; then
                fsdata=$(df -Ph | head -1 | sed 's/^/   /')
                fstmp=$(df -Ph | grep -E "^/dev/" | grep -v "tmpfs" | head -3 | sed 's/^/   /')
            fi
            else 
                clear
        fi
        print_centered_header "Hardware Information"
        printf " ──────────────────────────────────────────────────────────────────────────────\n"
        case $page in
            1)  
                printf " %b%bPage 1 of $total_pages: System Overview%b\n\n" "${BOLD}" "${CYAN}" "${RESET}"
                
                printf " %b\n" "${CYAN}System Information:${RESET}"

                [ -n "$hostname" ] && printf "   Model:    %b%-26s%b" "${GREEN}" "$hostname" "${RESET}"
                [ -n "$mac" ] && printf "Device MAC: %b%s%b\n" "${GREEN}" "$mac" "${RESET}"
                
                if [ -f /etc/glversion ]; then
                    firmware=$(cat /etc/glversion 2>/dev/null)
                    [ -n "$firmware" ] && printf "   Firmware: %b%-26s%b" "${GREEN}" "$firmware" "${RESET}"
                fi

                [ -n "$sn" ] && printf "Device SN:  %b%s%b\n" "${GREEN}" "$sn" "${RESET}"

                if [ -f /proc/uptime ]; then
                    read -r uptime_seconds rest < /proc/uptime
                    uptime_raw=${uptime_seconds%.*}
                    up_d=$((uptime_raw / 86400))
                    up_h=$(( (uptime_raw % 86400) / 3600 ))
                    up_m=$(( (uptime_raw % 3600) / 60 ))
                    up_s=$(( uptime_raw % 60 ))
                    time_string=$(printf "%02d:%02d:%02d" "$up_h" "$up_m" "$up_s")  
                    printf "   Uptime:   %b%d Day(s), %-13s%b" "${GREEN}" "$up_d" "$time_string" "${RESET}"
                else
                    printf "   Uptime:   %b%-23s%b" "${YELLOW}" "Unknown" "${RESET}"
                fi

                [ ! -z "$ddns" ] && printf "   Device ID:  %b%s%b" "${GREEN}" "$ddns" "${RESET}"   
                
                printf "\n\n"
                printf " %b\n" "${CYAN}CPU:${RESET}"
                printf "   Vendor/Model:    %b%s%b\n" "${GREEN}" "$cpu_vendor_model" "${RESET}"
                [ -n "$cpu_cores" ] && printf "   Cores:           %b%-16s%b" "${GREEN}" "$cpu_cores" "${RESET}"
                [ -n "$cpu_freq" ] && printf "   Frequency:  %b%.0f MHz%b\n" "${GREEN}" "$cpu_freq" "${RESET}"
                
                cpu_temp=$(get_cpu_temp)
                if [ "$cpu_temp" = "unknown" ]; then
                    printf "   CPU Temperature: %b%-17s%b\033[K" "${YELLOW}" "Unknown" "${RESET}"
                else
                    printf "   CPU Temperature: %b%-17s%b\033[K" "${GREEN}" "$cpu_temp°C" "${RESET}"
                fi
                
                fan_speed=$(get_fan_speed)
                [ -n "$fan_speed" ] && printf "   Fan Speed:  %b%s RPM%b\033[K\n" "${GREEN}" "$fan_speed" "${RESET}"
                
                read -r cpu_label user nice system idle iowait irq softirq rest < /proc/stat
                total=$((user + nice + system + idle + iowait + irq + softirq))
                diff_total=$((total - prev_total))
                diff_idle=$((idle - prev_idle))
                if [ "$diff_total" -gt 0 ]; then
                    cpu_percentage=$(( (diff_total - diff_idle) * 100 / diff_total ))
                fi
                prev_total=$total
                prev_idle=$idle
                [ -n "$cpu_percentage" ] && printf "   CPU Usage:       %b%-5s%b %-10s" "${GREEN}" "$cpu_percentage%" "${RESET}" ""
                
                read -r load_1 load_5 load_15 rest < /proc/loadavg
                cpu_load="${load_1}, ${load_5}, ${load_15}"
                [ -n "$cpu_load" ] && printf "   Load Avg:   %b%s%b\033[K\n" "${GREEN}" "$cpu_load" "${RESET}"

                printf "\n %b\n" "${CYAN}Memory:${RESET}"
                
                get_mem_stats
                mem_display=$(
                printf "   Soldered RAM:    %b%-9s %-6s%b" "${GREEN}" "$mem_rounded MB" "" "${RESET}"
                printf "   Free RAM:   %b%s%b\n" "${GREEN}" "$mem_free MB" "${RESET}"
                printf "   Total Usable:    %b%-9s %-6s%b" "${GREEN}" "$mem_total MB" "" "${RESET}"
                printf "   Used RAM:   %b%d MB (%d.%d%%)%b\033[K\n" "${GREEN}" "$mem_used" "$mem_p_whole" "$mem_p_decimal" "${RESET}"
                )
                printf "%b\n" "$mem_display\n"

                printf " %b\n" "${CYAN}Storage:${RESET}"
                printf "$storage_info\n"
                
                printf "\n %b\n" "${CYAN}Filesystem Usage:${RESET}"
                printf "%b\n%b\n" "$fsdata" "$fstmp"
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
                
                # --- 1. Map Discovery ---
                port_map="|"
                sw_list=$(swconfig list 2>/dev/null)
                if [ -n "$sw_list" ] && [ -f "/etc/board.json" ]; then
                    lan_ports=$(grep -B 1 '"role": "lan"' /etc/board.json | grep '"num":' | grep -oE '[0-9]+' | tr '\n' ' ')
                    current_label=1
                    for p in $(echo "$lan_ports" | tr ' ' '\n' | sort -rn); do
                        port_map="${port_map}P${p}:LAN${current_label}|"
                        current_label=$((current_label + 1))
                    done
                    wan_p=$(grep -B 1 '"role": "wan"' /etc/board.json | grep '"num":' | grep -oE '[0-9]+' | head -n 1)
                    [ -n "$wan_p" ] && port_map="${port_map}P${wan_p}:WAN|"
                fi

                # --- 2. Logical Interfaces ---
                printf " %b\n" "${CYAN}Network Interfaces (Logical/DSA):${RESET}"
                ip -br link show 2>/dev/null | grep -E "eth|lan|wan|br-" | while read iface state rest; do
                    base_iface=$(echo "$iface" | cut -d'@' -f1 | cut -d. -f1)
                    speed_raw=$(cat "/sys/class/net/$base_iface/speed" 2>/dev/null)
                    
                    # Format Speed string safely
                    if [ "$speed_raw" = "10000" ]; then spd="10Gbps"
                    elif [ -n "$speed_raw" ] && [ "$speed_raw" != "-1" ]; then spd="${speed_raw}Mbps"
                    else spd=""; fi

                    # Use printf with variables outside the format string to prevent escape char errors
                    if [ -n "$spd" ] && [ "$speed_raw" -ge 5000 ]; then
                        printf "   %-17s: %b%-5s%b %-12s %b%s%b\n" "$iface" "${GREEN}" "$state" "${RESET}" "$spd" "${CYAN}" "[Internal Trunk]" "${RESET}"
                    elif [ -n "$spd" ]; then
                        printf "   %-17s: %b%-5s%b %-12s\n" "$iface" "${GREEN}" "$state" "${RESET}" "$spd"
                    else
                        printf "   %-17s: %b%-5s%b\n" "$iface" "${GREEN}" "$state" "${RESET}"
                    fi
                done
                
                # --- 3. Physical Switch ---
                if [ -n "$sw_list" ]; then
                    printf "\n %b\n" "${CYAN}Physical Chassis Ports:${RESET}"
                    echo "$sw_list" | awk '{print $2}' | while read sw; do
                        sw_model=$(echo "$sw_list" | grep "$sw" | awk -F' - ' '{print $2}')
                        p_count=$(swconfig dev "$sw" help 2>&1 | grep -oE "ports: [0-9]+" | awk '{print $2}')
                        
                        printf "   %b%s (%s)%b\n" "${YELLOW}" "$sw" "$sw_model" "${RESET}"
                        printf "     Map: [ "
                        for i in $(seq 0 $((p_count - 1))); do
                            if swconfig dev "$sw" port "$i" get link 2>/dev/null | grep -q "link:up"; then
                                printf "%b$i%b " "${GREEN}" "${RESET}"
                            else
                                printf "%b$i%b " "${RED}" "${RESET}"
                            fi
                        done
                        printf "]\n"

                        for i in $(seq 0 $((p_count - 1))); do
                            link_info=$(swconfig dev "$sw" port "$i" get link 2>/dev/null)
                            if echo "$link_info" | grep -q "link:up"; then
                                h_label=$(echo "$port_map" | grep -o "|P$i:[^|]*" | cut -d: -f2)
                                # Standardize speed labels (remove baseT for cleanliness)
                                spd=$(echo "$link_info" | grep -oE "[0-9]+(baseT|Mbps|Gbps)" | sed 's/baseT/Mbps/' | sed 's/10000Mbps/10Gbps/' || echo "UP")
                                
                                [ -z "$h_label" ] && h_label="Port $i"
                                full_label="$h_label (P$i)"

                                if [[ "$spd" == *"10G"* ]]; then
                                    printf "     └─ %b%-12s%b: %bUP%b    %-12s %b(Internal)%b\n" "${YELLOW}" "$full_label" "${RESET}" "${GREEN}" "${RESET}" "$spd" "${CYAN}" "${RESET}"
                                else
                                    printf "     └─ %b%-12s%b: %bUP%b    %-12s\n" "${YELLOW}" "$full_label" "${RESET}" "${GREEN}" "${RESET}" "$spd"
                                fi
                            fi
                        done
                    done
                    printf "\n %bLegend: %bGreen=UP %bRed=DOWN %bCyan=Internal %bYellow=Chassis Label%b\n" "${BOLD}" "${GREEN}" "${RED}" "${CYAN}" "${YELLOW}" "${RESET}"
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
        
        printf " ──────────────────────────────────────────────────────────────────────────────\n"
        printf " [P] Previous   "
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
        
        if [ "$page" -eq 1 ]; then
            read -t 1 -n 1 nav_choice
            refresh_counter=$((refresh_counter + 1))
            [ "$refresh_counter" -gt 1000 ] && refresh_counter=0
            printf '\033[?25h'
        else
            nav_choice=$(read_single_char)
        fi
        
        case "$nav_choice" in
            p|P|b|B) [ $page -gt 1 ] && page=$((page - 1)) && clear;;
            n|N) [ $page -lt $total_pages ] && page=$((page + 1)) && clear;;
            1|2|3|4) 
                if [ "$page" -ne "$nav_choice" ]; then
                    page=$nav_choice
                    clear
                fi
                ;;
            0) return ;;
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

        if is_agh_running; then
            agh_pid=$(pidof AdGuardHome)
        else
            agh_pid=""
        fi

        printf " %b\n" "${CYAN}CURRENT STATUS${RESET}"
        if [ -z "$agh_pid" ]; then
            printf "   Running: ❌\n"
        else
            printf "   Running: ✅ (PID: %s)\n" "$agh_pid"
        fi

        if grep -q -- "--no-check-update" "$AGH_INIT"; then
            printf "   UI Updates: %bDISABLED%b\n" "${RED}" "${RESET}"
        else
            printf "   UI Updates: %bENABLED%b\n" "${GREEN}" "${RESET}"
        fi

        up_conf="/etc/sysupgrade.conf"
        updates_persist="0"

        if [ -s "$up_conf" ]; then
            updates_persist="1"
            for entry in "/usr/bin/AdGuardHome" "/etc/init.d/adguardhome" "/etc/AdGuardHome/config.yaml"; do
                if ! grep -qFx "$entry" "$up_conf" 2>/dev/null; then
                    updates_persist="0"
                    break
                fi
            done
        fi

        if [ "$updates_persist" -eq "1" ]; then
            printf "   Update Persistence: %bENABLED%b\n\n" "${GREEN}" "${RESET}"
        else
            printf "   Update Persistence: %bDISABLED%b\n\n" "${RED}" "${RESET}"
        fi
        
        printf "1️⃣  Enable UI Updates\n"
        printf "2️⃣  Disable UI Updates\n"
        printf "3️⃣  Enable update persistence across firmware updates\n"
        printf "4️⃣  Disable update persistence across firmware updates\n"
        printf "0️⃣  Return to previous menu\n"
        printf "❓ Help\n"
        printf "\nChoose [1-4/0/?]: "
        read -r agh_choice
        printf "\n"
        
        case $agh_choice in
            1)
                if grep -q -- "--no-check-update" "$AGH_INIT"; then
                    if [ "$updates_persist" -eq 0 ]; then
                        print_warning "UI updates are currently set to not persist across firmware updates.\n   Enabling UI updates may cause compatibility issues during firmware\n   updates due to legacy binaries being reinstalled. Consider enabling\n   update persistence to avoid this problem.\n"
                    else
                        print_info "UI updates are currently set to persist across firmware updates.\n"
                    fi
                    printf "Proceed with changes? [y/N]: "; read -r confirm ; printf "\n"
                    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue

                    sed -i 's/--no-check-update[[:space:]]*//g' "$AGH_INIT"
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
                printf "Disable UI updates? [y/N]: "; read -r confirm ; printf "\n"
                [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue
                
                if ! grep -q -- "--no-check-update" "$AGH_INIT"; then
                    sed -i '/procd_set_param command/ s/ \(-c\|--config\)/ --no-check-update \1/' "$AGH_INIT"
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
            3)
                if [ "$updates_persist" -eq 0 ]; then
                    printf "Enable update persistence across firmware updates? [y/N]: "; read -r confirm ; printf "\n"
                    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue
                    
                    [ ! -f "$up_conf" ] && touch "$up_conf"
                   
                    for entry in "/usr/bin/AdGuardHome" "/etc/init.d/adguardhome" "/etc/AdGuardHome/config.yaml"; do
                        grep -qFx "$entry" "$up_conf" || echo "$entry" >> "$up_conf"
                    done
                    print_success "Update persistence enabled in $up_conf"
                else
                    print_warning "Update persistence is already enabled"
                fi
                press_any_key
                ;;
            4)
                if [ "$updates_persist" -eq 1 ]; then
                    printf "Disable update persistence across firmware updates? [y/N]: "; read -r confirm ; printf "\n"
                    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue
                    sed -i "/\/usr\/bin\/AdGuardHome/d" /etc/sysupgrade.conf
                    sed -i "/\/etc\/init.d\/adguardhome/d" /etc/sysupgrade.conf
                    sed -i "/\/etc\/AdGuardHome\/config.yaml/d" /etc/sysupgrade.conf
                    print_success "Update persistence disabled in $up_conf"
                else
                    print_warning "Update persistence is already disabled"
                fi
                press_any_key
                ;;
            \?|h|H|❓)
                show_agh_ui_help
                ;;
            0)
                return
                ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# -----------------------------
# AdGuardHome Storage Management
# -----------------------------
show_agh_storage_help() {
    clear
    print_centered_header "AdGuardHome Filter Space Limit - Help"
    
    cat << 'HELPEOF'
AdGuardHome Filter Space Limit – BE3600 & Similar Models

Why the limit exists
────────────────────
On 512MB RAM routers (MT3600BE, some newer GL models), GL.iNet creates a 10MB file 
and mounts it as /etc/AdGuardHome/data/filters. This caps filter cache space to 
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
            df -Ph "$AGH_WORKDIR/data" 2>/dev/null | tail -1 | awk '{printf "   Total: %s | Used: %s | Free: %s\n", $2, $3, $4}'
        fi
        
        if [ -d "$AGH_WORKDIR/data/filters" ]; then
            printf "\n %b\n" "${CYAN}$AGH_WORKDIR/data/filters Directory:${RESET}"
            df -Ph "$AGH_WORKDIR/data/filters" 2>/dev/null | tail -1 | awk '{printf "   Total: %s | Used: %s | Free: %s\n", $2, $3, $4}'
        fi     
        
        limit_active=0
        if grep -q "$AGH_WORKDIR/data/filters" /proc/mounts; then
            limit_active=1
            # Calculate actual size from the mount point
            current_limit=$(df -Pm "$AGH_WORKDIR/data/filters" | tail -1 | awk '{print $2}')
            printf "   Filter Space Limit: %bACTIVE (%sMB)%b\n" "${YELLOW}" "$current_limit" "${RESET}"
        else
            printf "   Filter Space Limit: %bINACTIVE%b\n" "${GREEN}" "${RESET}"
        fi
        
        printf "\n1️⃣  Remove Filter Space Limitation\n"
        printf "2️⃣  Re-enable Filter Space Limitation\n"
        printf "0️⃣  Return to previous menu\n"
        printf "❓ Help\n"
        printf "\nChoose [1-2/0/?]: "
        read -r storage_choice
        printf "\n"

        local exec_pattern="^[[:space:]]*mount_filter_img[[:space:]]+"
        local comment_pattern="^[[:space:]]*#[[:space:]]*mount_filter_img[[:space:]]+"
        
        case $storage_choice in
            1)
                if [ "$limit_active" -eq 0 ]; then
                    print_warning "Filter space limitation is already INACTIVE on the system."
                    press_any_key; continue
                fi

                if ! grep -qE "$exec_pattern" "$AGH_INIT"; then
                    print_error "Could not find a feature call to disable."
                    press_any_key; continue
                fi
                
                cat << 'WARNEOF'
GL.iNet (MT3600BE & similar models) limits AdGuardHome filter cache to 10MB 
by creating a small tmpfs/loop-mounted partition at /etc/AdGuardHome/data/filters.

Removing this limit allows larger/more filter lists, but may cause high RAM usage 
and instability on 512MB devices when filters are big or many are enabled.
WARNEOF
                
                if ! swapon -s 2>/dev/null | grep -q zram; then
                    printf "\n"
                    print_warning "WARNING: Zram swap is NOT enabled!\n"
                    print_info "It is strongly recommended to enable zram swap before adding aditional filter lists."
                fi
                
                printf "\n%b" "${YELLOW}Remove the 10MB limit anyway? [y/N]: ${RESET}"
                read -r confirm
                printf "\n"
                if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                    printf "Operation cancelled.\n"
                    press_any_key
                    continue
                fi
                
                if is_agh_running; then
                    agh_pid=$(pidof AdGuardHome)
                    $AGH_INIT stop >/dev/null 2>&1; sleep 1
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
                
                sed -i "s|^\([[:space:]]*\)\(mount_filter_img[[:space:]]\)|\1# \2|" "$AGH_INIT"
                print_success "Disabled execution call in init script"
                
                if [ -n "$agh_pid" ]; then
                    $AGH_INIT start >/dev/null 2>&1; sleep 2
                    if is_agh_running; then
                        print_success "AdGuardHome restarted successfully"
                        print_success "Filter space limit removed!"
                    else
                        print_error "Failed to restart AdGuardHome"
                    fi
                fi
                
                press_any_key
                ;;
            2)
                if [ "$limit_active" -eq 1 ]; then
                    print_warning "Filter space limitation is already ACTIVE."
                    press_any_key; continue
                fi
                
                if ! grep -q "mount_filter_img" "$AGH_INIT"; then
                    print_warning "Filter space limitation feature is not supported on this device/firmware."
                    press_any_key
                    continue
                fi

                if grep -qE "$exec_pattern" "$AGH_INIT"; then
                    print_warning "Filter space limitation is already enabled or not supported on this device/firmware."
                    press_any_key; continue
                fi

                if ! grep -qE "$comment_pattern" "$AGH_INIT"; then
                    print_error "Could not find a feature call to re-enable."
                    press_any_key; continue
                fi
                
                if is_agh_running; then
                    agh_pid=$(pidof AdGuardHome)
                    $AGH_INIT stop >/dev/null 2>&1; sleep 1
                else
                    agh_pid=""
                fi
                
                sed -i "s|^\([[:space:]]*\)#[[:space:]]*\(mount_filter_img[[:space:]]\)|\1\2|" "$AGH_INIT"
                print_success "Re-enabled execution call in init script"
                
                if [ -n "$agh_pid" ]; then
                    $AGH_INIT start >/dev/null 2>&1; sleep 2
                    if is_agh_running; then
                        print_success "AdGuardHome restarted successfully"
                        print_success "Filter space limit re-enabled!"
                    else
                        print_error "Failed to restart AdGuardHome"
                    fi
                fi
                
                press_any_key
                ;;
            \?|h|H|❓)
                show_agh_storage_help
                ;;
            0)
                return
                ;;
            *) print_error "Invalid option"; sleep 1 ;;
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
            printf " [A] All   [N] None   [#] Toggle   [C] Confirm   [0] Cancel   [?] Help\n"
            printf " Enter command: "
            read -r input

            case "$input" in
                a|A) sed -i 's/\(.*|.*|.*|.*|\)0\(|.*|.*\)/\11\2/' "$LISTS_DATA" ;;
                n|N) sed -i 's/\(.*|.*|.*|.*|\)1\(|.*|.*\)/\10\2/' "$LISTS_DATA" ;;
                [0-9]*)
                    if [ "$input" != "0" ]; then
                        num="$input"
                        awk -F'|' -v t="$num" 'BEGIN{OFS="|"} {if($1==t) $5=($5==1?0:1); print}' "$LISTS_DATA" > "$LISTS_DATA.tmp" && mv "$LISTS_DATA.tmp" "$LISTS_DATA"
                    else
                        # If it is exactly 0, handle it as the cancel command
                        rm -f "$LISTS_DATA"; return
                    fi
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

                    $AGH_INIT stop >/dev/null 2>&1; sleep 1

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
                    $AGH_INIT start >/dev/null 2>&1; sleep 2
                     if ! is_agh_running; then
                        printf "\n"
						print_error "AdGuardHome failed to start! Reverting..."
                        cp "$AGH_CONFIG" "${AGH_CONFIG}.error.${stamp}"
                        cp "$BACKUP_FILE" "$AGH_CONFIG"
                        $AGH_INIT start >/dev/null 2>&1; sleep 2
                        if ! is_agh_running; then
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
                *) print_error "Invalid option"; sleep 1 ;;
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
   - Uses 'apache' to generate a secure Bcrypt hash.
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
        print_warning "No password currently set. This will create a new username and password."
    fi
    printf "Confirm to proceed? [y/N]: "
    read -r confirm
    printf "\n"
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return

    # Dependency Check
    if ! command -v htpasswd >/dev/null 2>&1; then
        print_info "Installing apache utils...\n"
        check_opkg_updated
        opkg install apache >/dev/null 2>&1
        if ! command -v htpasswd >/dev/null 2>&1; then
            print_error "Failed to install apache utils. Cannot proceed."
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

    # --- Stopping AGH before config changes ---
    $AGH_INIT stop >/dev/null 2>&1; sleep 1

    local ESC_HASH=$(echo "$BCRYPT_HASH" | sed 's/[&]/\\&/g')
    
    if grep -q "users: \[\]" "$AGH_CONF"; then
        # Case A: Empty list. Replace line with block.
        sed -i "\|users: \[\]|c\users:\n  - name: $user_name\n    password: \"$ESC_HASH\"" "$AGH_CONF"
    elif grep -q "^users:" "$AGH_CONF"; then
        # Case B: Check if next two lines are - name and password
        line_num=$(grep -n "^users:" "$AGH_CONF" | cut -d: -f1)
        check_name=$(sed -n "$((line_num+1))p" "$AGH_CONF")
        check_pass=$(sed -n "$((line_num+2))p" "$AGH_CONF")

        if echo "$check_name" | grep -q " - name:" && echo "$check_pass" | grep -q "password:"; then
            sed -i "$((line_num+1))s|- name: .*|- name: $user_name|" "$AGH_CONF"
            sed -i "$((line_num+2))s|password: .*|password: \"$ESC_HASH\"|" "$AGH_CONF"
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
    $AGH_INIT start >/dev/null 2>&1; sleep 2
    if ! is_agh_running; then
        print_error "Service failed to start! Rolling back..."
        cp "$BACKUP_FILE" "$AGH_CONF"
        $AGH_INIT start >/dev/null 2>&1; sleep 2
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
                printf "Confirm [y/N]: "
                read -r confirm
                printf "\n"
                [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue

                BACKUP_FILE="$AGH_CONF.backup.$TIMESTAMP"
                cp "$AGH_CONF" "$BACKUP_FILE"
                $AGH_INIT stop >/dev/null 2>&1; sleep 1

                # Find users: block and replace with users: []
                line_num=$(grep -n "^users:" "$AGH_CONF" | cut -d: -f1)
                # Delete the next two lines (- name and password) then change users: to users: []
                if ! grep -q "users: \[\]" "$AGH_CONF"; then
                    sed -i "$((line_num+1)),$((line_num+2))d" "$AGH_CONF"
                fi
                sed -i "${line_num}s/users:.*/users: []/" "$AGH_CONF"

                $AGH_INIT start >/dev/null 2>&1
                sleep 2
                if ! is_agh_running; then
                    print_error "Service failed to start! Rolling back..."
                    cp "$BACKUP_FILE" "$AGH_CONF"
                    $AGH_INIT start >/dev/null 2>&1; sleep 2
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
  active, it restricts filter space to prevent storage exhaustion.
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
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

manage_agh_backups() {
    while true; do
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
        if [ -z "$selected_ts" ]; then 
            print_error "Invalid selection"; sleep 1; continue
        fi

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
                    $AGH_INIT stop >/dev/null 2>&1; sleep 1
                    [ "$fix_cfg" = "Y" ] && cp "/etc/AdGuardHome/config.yaml.backup.$selected_ts" "/etc/AdGuardHome/config.yaml"
                    [ "$fix_bin" = "Y" ] && cp "/usr/bin/AdGuardHome.backup.$selected_ts" "/usr/bin/AdGuardHome"
                    [ "$fix_ini" = "Y" ] && cp "/etc/init.d/adguardhome.backup.$selected_ts" "/etc/init.d/adguardhome"
                    $AGH_INIT start >/dev/null 2>&1; sleep 2
                    printf "\n"
                    print_success "Restore complete!"; press_any_key; return ;;
                0) return ;;
                *) print_error "Invalid option"; sleep 1 ;;
            esac
        done
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
        printf " [A] All   [N] None   [#] Toggle   [C] Confirm   [0] Cancel\n"
        printf " Enter command: "
        read -r input
        local cmd=$(echo "$input" | tr '[:upper:]' '[:lower:]')

        case "$cmd" in
            a) sed -i 's/|0$/|1/' "$map_file" ;;
            n) sed -i 's/|1$/|0/' "$map_file" ;;
            [1-9]*) 
                if grep -q "^$cmd|" "$map_file"; then
                    local current_state=$(grep "^$cmd|" "$map_file" | cut -d'|' -f3)
                    local new_state=$((1 - current_state))
                    sed -i "s/^\($cmd|[^|]*|\).*/\1$new_state/" "$map_file"
                else
                    print_error "Index $cmd not found"; sleep 1
                fi ;;
            c)
                if ! grep -q "|1$" "$map_file"; then
                    printf "\n"
                    print_error "No backups selected."; press_any_key; continue
                fi
                printf "\n"
                print_warning "WARNING: You are about to permanently delete selected backups."
                printf "Confirm deletion? [y/N]: "; read -r confirm
                case "$confirm" in
                    y|Y)
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
                    return ;;
                    *) print_error "Deletion cancelled." ; press_any_key ; continue ;;
                esac ;;
            0) rm -f "$map_file"; return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

sub_setup_config() {
    while true; do
        clear
        print_centered_header "AdGuardHome Setup, Access & UI Updates"
        printf "1️⃣  Filter Storage Space Limit\n"
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
            *) print_error "Invalid option"; sleep 1;;
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
            *) print_error "Invalid option"; sleep 1;;
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
                   print_warning "Service is RUNNING. Do you want to [D]isable, [R]estart, or [0] Cancel?"
                   printf "Choose [D/R/0]: "; read -r confirm
                   if [ "$confirm" = "d" ] || [ "$confirm" = "D" ]; then
                       uci set adguardhome.config.enabled='0' && uci set adguardhome.config.dns_enabled='0' && uci commit adguardhome
                       $AGH_INIT stop >/dev/null 2>&1; sleep 1; printf "\n"; print_success "Service Disabled"
                   elif [ "$confirm" = "r" ] || [ "$confirm" = "R" ]; then
                       $AGH_INIT restart >/dev/null 2>&1; sleep 2; printf "\n"; print_success "Service Restarted"
                   fi
               else
                   printf "\n"
                   print_warning "Service is STOPPED. Enable now?"
                   printf "Confirm [y/N]: "; read -r confirm
                   if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                       uci set adguardhome.config.enabled='1' && uci set adguardhome.config.dns_enabled='1' && uci commit adguardhome
                       $AGH_INIT enable >/dev/null 2>&1; sleep 1; $AGH_INIT start >/dev/null 2>&1; sleep 2; printf "\n"; print_success "Service Enabled"
                   fi
               fi
               press_any_key ;;
            2) 
               clear
               print_centered_header "AdGuardHome System Logs (Ctrl+C to exit)"
               sleep 1
               trap 'printf "\n\n"; print_warning "Stopping log viewing..."' INT
               logread -l 20 -e "AdGuardHome" 2>/dev/null
               logread -f -e "AdGuardHome" 2>/dev/null
               trap - INT
               press_any_key
               ;;
            3) 
               printf "\n"
               print_warning "Clear all cached filter files?"
               printf "Confirm [y/N]: "; read -r confirm
               if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                   local wd=$(get_agh_workdir)
                   rm -rf "${wd:-/etc/AdGuardHome}/data/filters/"* 2>/dev/null
                   $AGH_INIT restart >/dev/null 2>&1; printf "\n"; print_success "Filters Purged"
                   cached_rules="" 
               fi
               press_any_key ;;
            0) break ;;
            *) print_error "Invalid option"; sleep 1;;
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
    print_warning "WARNING: This will restore factory system files and defaults from /rom"
    printf "Confirm restore? [y/N]: "; read -r confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { printf "\n"; print_info "Operation cancelled."; press_any_key; return; }

    # --- 1. Pre-Check State & Stop Phase ---
    # Call the function directly to check the exit status
    is_agh_running && was_running=1
    
    if [ "$(uci -q get adguardhome.config.enabled)" = "1" ]; then
        was_uci_enabled=1
    fi

    if [ "$was_running" -eq 1 ]; then
        printf "\n"
        print_info "AdGuardHome is currently running. Stopping service..."
        [ -f "$L_INIT" ] && $L_INIT stop >/dev/null 2>&1; sleep 1
        sleep 1
        if is_agh_running; then
            kill -9 $(pidof AdGuardHome) >/dev/null 2>&1; sleep 1
        fi
        print_success "Service stopped successfully."
    fi

    # --- 2. Restore Files from ROM ---
    [ -f "/rom$L_INIT" ] && cp -f "/rom$L_INIT" "$L_INIT" && chmod +x "$L_INIT" && init_ok=1
    [ -f "/rom$L_BIN" ]  && cp -f "/rom$L_BIN" "$L_BIN"   && chmod +x "$L_BIN"  && bin_ok=1
    [ -f "/rom$L_CONF" ] && cp -f "/rom$L_CONF" "$L_CONF" && conf_ok=1
    
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
            uci set adguardhome.config.enabled='1' && uci set adguardhome.config.dns_enabled='1' && uci commit adguardhome
            $L_INIT enable >/dev/null 2>&1; sleep 1
            print_success "Full recovery successful! AdGuardHome auto-start re-enabled."
            printf "\n"
        else
            printf "\n"
            print_warning "AdGuardHome was disabled in UCI. Enable it now?"
            printf "Confirm [y/N]: "; read -r confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then 
                uci set adguardhome.config.enabled='1' && uci set adguardhome.config.dns_enabled='1' && uci commit adguardhome
                $L_INIT enable >/dev/null 2>&1; sleep 1
                print_success "AdGuardHome enabled in GL-WebUI and UCI.\n"
                was_uci_enabled=1
            fi
        fi
        
        # Handle operational state (Running)
        if [ "$was_running" -eq 1 ]; then
            print_info "Automatically restarting service..."
            $L_INIT start >/dev/null 2>&1; sleep 2; print_success "Service restored to running state."
        elif [ "$was_uci_enabled" -eq 1 ]; then
            print_warning "AdGuardHome is enabled but not running. Start it now?"
            printf "Confirm [y/N]: "; read -r confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then 
                printf "\n"
                print_info "Starting AdGuardHome...\n"
                $L_INIT start >/dev/null 2>&1; sleep 2; print_success "Service started successfully."
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
    filt_f=$(get_free_space "$data_dir/filters")

    # 5. Storage Metric: Query Logs (DBs + JSON)
    local q_bytes=0
    for f in "$data_dir/stats.db" "$data_dir/sessions.db" "$data_dir/querylog.json"; do
        [ -f "$f" ] && q_bytes=$((q_bytes + $(ls -nl "$f" | awk '{print $5}')))
    done
    qlog_u=$(awk "BEGIN {printf \"%.1fM\", ${q_bytes:-0}/1048576}")
    qlog_f=$(get_free_space "$data_dir")

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
            *) print_error "Invalid option"; sleep 1;;
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
• Routers with 512MB flash or less will have a forced limit for AdGuardHome allow/block lists.
  See Option 3 - Manage AdGuardHome Storage

In this menu you can:
1. Install & enable zram swap
2. Disable it (stops and disables on boot)
3. Completely uninstall the package
HELPEOF
    
    press_any_key
}

manage_zram() {
    local up_conf="/etc/sysupgrade.conf"
    local laz_list="/etc/lazarus.list"

    while true; do
        zram_persisting=0
        if grep -qFx "/etc/init.d/zram" "$up_conf" 2>/dev/null; then
            zram_persisting=1
        fi

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
        if [ "$zram_persisting" -eq 1 ]; then
                printf "   Persistence: %bENABLED%b\n\n" "${GREEN}" "${RESET}"
            else
                printf "   Persistence: %bDISABLED%b\n\n" "${YELLOW}" "${RESET}"
        fi
        
        printf "1️⃣  Install and Enable\n"
        printf "2️⃣  Disable\n"
        printf "3️⃣  Toggle Persistence\n"
        printf "4️⃣  Uninstall Package\n"
        printf "0️⃣  Return to previous menu\n"
        printf "❓ Help\n"
        printf "\nChoose [1-4/0/?]: "
        read -r zram_choice
        printf "\n"
        
        case $zram_choice in
            1)
                if ! opkg list-installed | grep -q "^zram-swap"; then
                    print_warning "zram-swap not installed, installing...\n"
                    check_opkg_updated
                    opkg install zram-swap >/dev/null 2>&1
                    if opkg list-installed | grep -q "^zram-swap"; then
                        print_success "zram-swap package installed\n"
                    else
                        print_error "Failed to install zram-swap\n"
                        press_any_key
                        continue
                    fi
                fi
                
                if [ -f /etc/init.d/zram ]; then
                    print_info "Enabling and starting zram swap\n"
                    /etc/init.d/zram enable >/dev/null 2>&1; sleep 1
                    /etc/init.d/zram start >/dev/null 2>&1; sleep 2
                    print_success "Zram swap enabled and started\n"
                    
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
                    /etc/init.d/zram stop >/dev/null 2>&1; sleep 1
                    /etc/init.d/zram disable >/dev/null 2>&1; sleep 1
                    print_success "Zram swap disabled and stopped"
                else
                    print_warning "Zram swap is not installed"
                fi
                press_any_key
                ;;
            3)
                if [ ! -f /etc/init.d/zram ]; then
                    print_error "Zram swap is not installed."
                else
                    local z_paths="/etc/init.d/zram /etc/config/system"
                    
                    if [ "$zram_persisting" -eq 0 ]; then
                        for p in $z_paths; do
                            grep -qFx "$p" "$up_conf" || echo "$p" >> "$up_conf"
                        done
                        grep -qFx "zram-swap" "$laz_list" 2>/dev/null || echo "zram-swap" >> "$laz_list"
                        create_lazarus_hook
                        print_success "Zram persistence enabled."
                    else
                        for p in $z_paths; do
                            sed -i "\|$p|d" "$up_conf" 2>/dev/null
                        done
                        sed -i "\|zram-swap|d" "$laz_list" 2>/dev/null
                        print_warning "Zram persistence disabled."
                    fi
                fi
                press_any_key
                ;;
            4)
                if opkg list-installed | grep -q "^zram-swap"; then
                    printf "%b" "${YELLOW}Remove zram-swap package? [y/N]: ${RESET}"
                    read -r confirm
                    printf "\n"
                    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                        [ -f /etc/init.d/zram ] && /etc/init.d/zram stop >/dev/null 2>&1; sleep 1
                        opkg remove zram-swap >/dev/null 2>&1
                        
                        # Added cleanup to match Package Manager behavior
                        for p in /etc/init.d/zram /etc/config/system; do
                            sed -i "\|$p|d" "$up_conf" 2>/dev/null
                        done
                        sed -i "\|zram-swap|d" "$laz_list" 2>/dev/null
                        
                        print_success "zram-swap package removed"
                    else
                        printf "Removal cancelled."
                    fi
                else
                    print_warning "zram-swap package is not installed"
                fi
                press_any_key
                ;;
            \?|h|H|❓)
                show_zram_help
                ;;
            0)
                return
                ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}


# -----------------------------
# System Tweaks
# -----------------------------

# --- Fan Management Module ---

show_fan_help() {
    clear
    print_centered_header "Fan Management - Help"
    
    cat << 'HELPEOF'
Fan Management – Quick Help

How the Fan Controller Works:
─────────────────────────────
The /usr/bin/gl_fan process uses a PID-style controller to manage speed 
based on three primary temperature setpoints.

The Setpoints Explained:
• Minimum: The temperature where the fan starts spinning at its lowest 
  voltage. Setting this higher keeps the fan off longer.
• Fan-On: The "Target" temperature. The controller will ramp the fan up 
  toward 100% speed as it approaches and exceeds this value.
• Warning: Primarily used for system logs and UI alerts. Usually set 
  equal to or slightly higher than the Fan-On setpoint.
• UI Max: This script's custom "Unlock." It extends the slider range 
  in the web interface, allowing you to set thresholds up to 120°C.

Thermal Hierarchy (Safety Rules):
─────────────────────────────────
To prevent logic loops, the following rules are enforced:
  Minimum ≤ Fan-On ≤ UI Max
  Warning must be between Minimum and UI Max.

Dynamic vs. Manual Mode:
• Dynamic: The system automatically adjusts RPM based on heat.
• Manual: Forces the fan to a specific percentage (0-100%). 
  Note: Manual mode persists until you re-enable Dynamic control.

Safety Warning:
────────────────
Extending limits beyond 100°C can lead to hardware throttling or 
emergency shutdowns. Most silicon is rated for ~105°C. Use 110°C+ 
only if you understand the thermal risks to your specific model.
HELPEOF
    
    press_any_key
}

manage_fan_settings() {
    current_model=$(cat /proc/gl-hw-info/model)

    reset_to_factory(){
        # 1. Restore the 'Engine' (The Library) and the 'Seed' (The ROM config)
        if [ -f "/rom/lib/functions/gl_util.sh" ]; then 
            cp "/rom/lib/functions/gl_util.sh" "/lib/functions/gl_util.sh"
        fi

        if [ -f "/rom/etc/config/glfan" ]; then 
            cp "/rom/etc/config/glfan" "/etc/config/glfan"
        fi
        
        # 2. Trigger the Internal Provisioner
        # This populates UCI with the REAL factory defaults for THIS specific model
        . /lib/functions/gl_util.sh
        fan_init
        uci commit glfan
        
        # 3. Restore Web UI Visuals & Logic from ROM
        if [ -f "/rom/www/views/gl-sdk4-ui-overview.common.js.gz" ]; then
            cp "/rom/www/views/gl-sdk4-ui-overview.common.js.gz" "/www/views/gl-sdk4-ui-overview.common.js.gz"
        fi
        
        local app_rom_gz=$(find /rom/www/js/ -name "app.*.js.gz" -type f | head -n 1)
        if [ -n "$app_rom_gz" ]; then
            cp "$app_rom_gz" "/www/js/$(basename "$app_rom_gz")"
        fi

        if [ -f "/rom/www/i18n/gl-sdk4-ui-overview.en.json" ]; then
            cp "/rom/www/i18n/gl-sdk4-ui-overview.en.json" "/www/i18n/gl-sdk4-ui-overview.en.json"
        fi
        
        /etc/init.d/gl_fan restart >/dev/null 2>&1
    }

    sync_system_and_ui() {
        # Start at a good working state
        reset_to_factory       
        
        local n_min=$1  # Minimum (The Floor)
        local n_cur=$2  # Fan-On (The current target)
        local n_wrn=$3  # Warning (The visual/system trigger)
        local n_max=$4  # Maximum (The Ceiling)
        
        local b_min=$((n_min - 1)) 
        local b_max=$((n_max + 1))
        local util_file="/lib/functions/gl_util.sh"

        # --- 1. System Logic & Backend Variable Sync ---
        # Patch the hardware floor comparisons in the fan control library
        sed -i "s/-lt 6[0-9]/-lt $n_min/g" "$util_file"
        sed -i "s/-lt 7[0-9]/-lt $n_min/g" "$util_file"

        # Use the model identifier to target the correct code block for assignments
        if awk "/$current_model[)]/,/;;/" "$util_file" | grep -q "temperature="; then
            sed -i "/$current_model[)]/,/;;/ s/\(minimum_temperature=\)[0-9]*/\1$n_min/" "$util_file"
            sed -i "/$current_model[)]/,/;;/ s/\([[:space:]]temperature=\)[0-9]*/\1$n_cur/" "$util_file"
        else
            sed -i "s/\(local minimum_temperature=\)[0-9]*/\1$n_min/" "$util_file"
            sed -i "s/\(local temperature=\)[0-9]*/\1$n_cur/" "$util_file"
        fi
        sed -i "s/warn_temperature=.*$/warn_temperature=\"$n_wrn\"/" "$util_file"

        # --- 2. UCI Persistence ---
        uci set glfan.globals.minimum_temperature="$n_min"
        uci set glfan.globals.temperature="$n_cur"
        uci set glfan.globals.warn_temperature="$n_wrn"
        uci commit glfan

        # --- 3. View Component Patching (UI Logic & Visuals) ---
        local view_gz="/www/views/gl-sdk4-ui-overview.common.js.gz"
        [ ! -f "$view_gz" ] && cp "/rom$view_gz" "$view_gz"
        gunzip -f "$view_gz"
        local v="/www/views/gl-sdk4-ui-overview.common.js"

        # SECTION A: Computed Property Overrides (Dynamic Shadowing)
        sed -i "s/minimum_temperature:t/minimum_temperature:ignore,t=$n_min/g" "$v"
        sed -i "s/maximum_temperature:t/maximum_temperature:ignore,t=$n_max/g" "$v"
        sed -i "s/maximumTemperature:()=>[0-9]*/maximumTemperature:()=>$n_max/g" "$v"

        # SECTION B: Literal Logic Guards (Integer Boundaries)
        sed -i "s/t<70/t<$n_min/g" "$v"
        sed -i "s/t>90/t>$n_max/g" "$v"
        sed -i "s/ature=70/ature=$n_min/g" "$v"
        sed -i "s/ature=90/ature=$n_max/g" "$v"

        # SECTION C: Universal Component Logic (Snap-Back Prevention)
        sed -i "s/t<this.minimumTemperature/t<$n_min/g" "$v"
        sed -i "s/t>this.maximumTemperature/t>$n_max/g" "$v"
        sed -i "s/this.temperature=this.minimumTemperature/this.temperature=$n_min/g" "$v"
        sed -i "s/this.temperature=this.maximumTemperature/this.temperature=$n_max/g" "$v"

        # SECTION D: Physical Slider Attributes (Visual Buffer)
        sed -i "s/attrs:{min:[^,]*[0-9a-zA-Z.-]*,max:[0-9a-zA-Z.+-]*/attrs:{min:$b_min,max:$b_max/g" "$v"

        # SECTION E: Slider Scale & Step Labels
        local marks_obj="${n_min}:'${n_min}°C'"
        local span=$((n_max - n_min))
        local interval=10
        [ "$span" -le 50 ] && interval=5
        for i in $(seq $((n_min + $interval)) "$interval" "$n_max"); do
            marks_obj="$marks_obj,$i:'$i°C'"
        done
        sed -i "s/marks:t.tMarks/marks:{$marks_obj}/g" "$v"

        # SECTION F: Information Strings (Info Box / Localization)
        local info_pattern="fan start is [^.]*"
        local info_replacement="fan start is $n_min °C ~ $n_max °C "
        sed -i "s/$info_pattern/$info_replacement/g" "$v"
        [ -f "/www/i18n/gl-sdk4-ui-overview.en.json" ] && \
        sed -i "s/$info_pattern/$info_replacement/g" "/www/i18n/gl-sdk4-ui-overview.en.json"

        # --- 4. Global Application Controller Patch (Validator Range) ---
        local app_gz=$(find /www/js/ -name "app.*.js.gz" -type f | head -n 1)
        if [ -n "$app_gz" ]; then
            gunzip -f "$app_gz"
            local app_file="${app_gz%.gz}"
            # Unlock the global validator range
            sed -i "s/[0-9]\{1,3\}||i<[0-9]\{2,3\}/${n_min}||i<$((n_max + 1))/g" "$app_file"
            # Prevent initial state snap-back on page load
            sed -i "s/temperature:6[90]/temperature:$n_cur/g" "$app_file"
            sed -i "s/temperature:76/temperature:$n_cur/g" "$app_file"
            gzip -f "$app_file"
        fi

        # 5. Deployment
        gzip -f "$v"
        /etc/init.d/gl_fan restart
    }
    
    while true; do
        
        # 1. State Capture & Fanless Detection
        has_fan=true
        [ ! -d "/sys/class/thermal/cooling_device0" ] && has_fan=false

        c_mode="DYNAMIC (System)"
        c_mode_color="${GREEN}"
        if ! pgrep -f '/usr/bin/gl_fan' >/dev/null; then
            c_mode="MANUAL (Static)"
            c_mode_color="${YELLOW}"
        fi
        
        c_temp_fmt=$(get_cpu_temp)
        c_fan_rpm="N/A"
        c_speed_pct=0
        
        if [ "$has_fan" = "true" ]; then
            c_fan_rpm=$(get_fan_speed)
            c_pwm=$(cat /sys/class/thermal/cooling_device0/cur_state 2>/dev/null)
            [ -z "$c_pwm" ] && c_pwm=0
            c_speed_pct=$(( (c_pwm * 100) / 255 ))
        fi

        # 2. Get Current UI Max Setpoint
        local view_gz="/www/views/gl-sdk4-ui-overview.common.js.gz"
        local util_file="/lib/functions/gl_util.sh"
        local attrs_block=$(gzip -dc "$view_gz" 2>/dev/null | grep -oE "attrs:\{min:[-0-9]+,max:[0-9]+")

        if [ -n "$attrs_block" ]; then
            raw_min=$(echo "$attrs_block" | cut -d: -f3 | cut -d, -f1)
            raw_max=$(echo "$attrs_block" | cut -d: -f4)
            u_min=$((raw_min + 1))
            ui_max=$((raw_max - 1))
        else
            u_min=$(gzip -dc "$view_gz" 2>/dev/null | grep -oE "minimumTemperature:[^}]*" | grep -oE "[0-9]{2,3}" | head -n 1)
            ui_max=$(gzip -dc "$view_gz" 2>/dev/null | grep -oE "maximumTemperature:[^}]*" | grep -oE "[0-9]{2,3}" | head -n 1)
        fi

        # --- 3. UCI Configuration State (The "Truth") ---
        u_cur=$(uci -q get glfan.globals.temperature)
        u_wrn=$(uci -q get glfan.globals.warn_temperature)

        # --- 4. Sanitization & Fallbacks ---
        [ -z "$u_min" ] && u_min=70
        [ -z "$ui_max" ] && ui_max=90
        [ -z "$u_cur" ] && u_cur=75
        [ -z "$u_wrn" ] && u_wrn=75

        clear
        print_centered_header "Fan Management"
        
        printf " %b\n" "${CYAN}STATUS${RESET}"
        if [ "$has_fan" = "false" ]; then
            printf "   Hardware:          %bNOT DETECTED (Fanless Unit)%b\n" "${RED}" "${RESET}"
        else
            printf "   Control Mode:      %b%s%b\n" "$c_mode_color" "$c_mode" "${RESET}"
            printf "   Current Speed:     %d%% (%s RPM)\n" "$c_speed_pct" "$c_fan_rpm"
        fi
        printf "   Temperature:       %b%s°C%b\n\n" "${WHITE}" "$c_temp_fmt" "${RESET}"

        printf " %b\n" "${CYAN}DYNAMIC SETTINGS${RESET}"
        printf "   Minimum Setpoint:  %s°C\n" "${u_min:-UNKNOWN}"
        printf "   Fan-On Setpoint:   %s°C\n" "${u_cur:-UNKNOWN}"
        printf "   Warning Setpoint:  %s°C\n" "${u_wrn:-UNKNOWN}"
        printf "   Max Setpoint (UI): %b%s°C%b\n\n" "${YELLOW}" "$ui_max" "${RESET}"

        if [ "$has_fan" = "false" ]; then
            print_warning "Fan settings are disabled on fanless hardware."
            printf "0️⃣  Return to previous menu\n"
        else
            printf "1️⃣  Set Static Fan Speed (0-100%%)\n"
            printf "2️⃣  Enable Dynamic Fan Control\n"
            printf "3️⃣  Set Minimum Setpoint\n"
            printf "4️⃣  Set Fan-On Setpoint\n"
            printf "5️⃣  Set Warning Setpoint\n"
            printf "6️⃣  Set UI Maximum Setpoint\n"
            printf "7️⃣  Reset to Factory Defaults\n"
            printf "0️⃣  Return to previous menu\n"
            printf "❓ Help\n"
        fi
        
        printf "\nChoose option: "
        read -r fan_choice
        printf "\n"

        if [ "$has_fan" = "false" ]; then
            case "$fan_choice" in
                0) return ;;
                \?|h|H|help|HELP) show_fan_help; continue ;;
                *) continue ;;
            esac
        fi

        case "$fan_choice" in
            1)
                printf "Enter Speed %% (0-100): "
                read -r pct
                printf "\n"
                pct=$(echo "$pct" | tr -dc '0-9')
                if [ -n "$pct" ] && [ "$pct" -le 100 ]; then
                    /etc/init.d/gl_fan stop >/dev/null 2>&1
                    echo "$(( (pct * 255 +50) / 100 ))" > /sys/class/thermal/cooling_device0/cur_state
                    print_success "Manual mode active: $pct%"
                else
                    print_error "Invalid input."
                fi
                press_any_key ;;
            2)
                /etc/init.d/gl_fan enable >/dev/null 2>&1
                /etc/init.d/gl_fan restart >/dev/null 2>&1
                print_success "Dynamic control restored"
                press_any_key ;;
            3)
                printf "Set new Minimum Setpoint (0°C - %s°C): " "$u_cur"
                read -r val
                val=$(echo "$val" | tr -dc '0-9')
                if [ -n "$val" ] && [ "$val" -le "$u_cur" ]; then
                    sync_system_and_ui "$val" "$u_cur" "$u_wrn" "$ui_max"
                    print_success "Minimum setpoint updated to ${val}°C (System & UI)."
                else
                    print_error "Must be a number and ≤ Fan-On ($u_cur°C)"
                fi
                press_any_key ;;
            4)
                printf "New Fan-On Setpoint (%s°C - %s°C): " "$u_min" "$ui_max"
                read -r val
                printf "\n"
                val=$(echo "$val" | tr -dc '0-9')
                if [ -n "$val" ] && [ "$val" -ge "$u_min" ] && [ "$val" -le "$ui_max" ]; then
                    sync_system_and_ui "$u_min" "$val" "$u_wrn" "$ui_max"
                    print_success "Fan-On setpoint updated"
                else
                    print_error "Must be between Min ($u_min°C) and UI Max ($ui_max°C)"
                fi
                press_any_key ;;
            5)
                printf "New Warning Setpoint (%s°C - %s°C): " "$u_min" "$ui_max"
                read -r val
                printf "\n"
                val=$(echo "$val" | tr -dc '0-9')
                if [ -n "$val" ] && [ "$val" -ge "$u_min" ] && [ "$val" -le "$ui_max" ]; then
                    sync_system_and_ui "$u_min" "$u_cur" "$val" "$ui_max"
                    print_success "Warning setpoint updated"
                else
                    print_error "Must be between Min ($u_min°C) and UI Max ($ui_max°C)"
                fi
                press_any_key ;;
            6)
                print_warning "DANGER: EXTENDING AND SETTING THERMAL LIMITS PAST 90°C MAY CAUSE DAMAGE TO YOUR DEVICE!"
                printf "Set new UI Maximum Setpoint (%s°C - 120°C): " "$u_cur"
                read -r val
                printf "\n"
                val=$(echo "$val" | tr -dc '0-9')
                if [ -n "$val" ] && [ "$val" -ge "$u_cur" ] && [ "$val" -le 120 ]; then
                    if [ "$val" -lt $u_wrn ]; then
                        print_warning "New UI Max is below current Warning setpoint. Adjusting Warning to match new UI Max.\n"
                        u_wrn="$val"
                    fi
                    sync_system_and_ui "$u_min" "$u_cur" "$u_wrn" "$val"
                    print_success "Max UI setpoint updated to ${val}°C."
                else
                    print_error "Must be between Fan-On ($u_cur°C) and 120°C"
                fi
                press_any_key ;;
            7)
                print_warning "Restoring to Factory Defaults..."
                reset_to_factory
                print_success "Factory defaults restored. Refresh browser."
                press_any_key ;;
            0) return ;;
            \?|h|H|❓) show_fan_help; continue ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

get_action_text() {
    local t_i=$1 local t_p=$2 local o_i=$3 local o_p=$4
    
    if [ "$t_i" -eq "$o_i" ] && [ "$t_p" -eq "$o_p" ]; then
        echo "No Change"
    elif [ "$t_i" -eq 1 ] && [ "$o_i" -eq 0 ]; then
        [ "$t_p" -eq 1 ] && echo "> Install + Persist" || echo "> Install Package"
    elif [ "$t_i" -eq 1 ] && [ "$o_i" -eq 1 ] && [ "$t_p" -ne "$o_p" ]; then
        [ "$t_p" -eq 1 ] && echo "> Enable Persistence" || echo "> Disable Persistence"
    elif [ "$t_i" -eq 0 ] && [ "$o_i" -eq 1 ]; then
        [ "$o_p" -eq 1 ] && echo "> Remove + Unpersist" || echo "> Remove Package"
    else
        echo "No Change"
    fi
}

create_lazarus_hook() {
    local hook="/etc/uci-defaults/99-lazarus"
    cat << 'EOF' > "$hook"
#!/bin/sh
# Lazarus Survival Engine - Post-Upgrade Package Restoration Hook
if [ -f /etc/lazarus.list ]; then
    opkg update
    cat /etc/lazarus.list | xargs opkg install
fi
# Re-persist the healer list itself
grep -qFx "/etc/lazarus.list" /etc/sysupgrade.conf || echo "/etc/lazarus.list" >> /etc/sysupgrade.conf
exit 0
EOF
    chmod +x "$hook"
}

manage_packages() {
    # Define the Utility Database (Package|Binary|Config/Service Files)
    # Types: R = Reinstall (Complex), B = Binary (Simple)
    local UTILITY_DB="zram-swap|/etc/init.d/zram|R|/etc/init.d/zram /etc/config/system
librespeed-go|/usr/bin/librespeed-go|R|/usr/bin/librespeed-go /etc/config/librespeed-go /etc/init.d/librespeed-go
stress|/usr/bin/stress|B|/usr/bin/stress
stress-ng|/usr/bin/stress-ng|B|/usr/bin/stress-ng
lscpu|/usr/bin/lscpu|B|/usr/bin/lscpu
apache|/usr/bin/htpasswd|R|/usr/bin/htpasswd
htop|/usr/bin/htop|B|/usr/bin/htop
rsync|/usr/bin/rsync|B|/usr/bin/rsync
vim-fuller|/usr/bin/vim|R|/usr/bin/vim
speedtest|/usr/bin/speedtest|B|/usr/bin/speedtest /root/.config/ookla/speedtest-cli.json"

    local map_file="/tmp/pkg_manage_map"
    local sys_conf="/etc/sysupgrade.conf"
    local laz_list="/etc/lazarus.list"
    
    # Initialization: Scan current system state
    init_system_state(){
    [ -f "$map_file" ] && rm -f "$map_file"
    local i=1
    echo "$UTILITY_DB" | while IFS='|' read -r name bin type paths; do
        local inst=0; [ -f "$bin" ] && inst=1
        local pers=0
        # Check if any of its paths are in sysupgrade.conf
        for p in $paths; do
            if grep -qFx "$p" "$sys_conf" 2>/dev/null; then pers=1; break; fi
        done
        # Format: Index|Name|Target_I|Target_P|Action|Type|Paths|Orig_I|Orig_P
        echo "$i|$name|$inst|$pers|No Change|$type|$paths|$inst|$pers" >> "$map_file"
        i=$((i+1))
    done
    }

    init_system_state

    while true; do
        clear
        print_centered_header "Package & Persistence Manager"
        printf "      Install Persist  Package Name        Planned Action\n"
        printf " ──────────────────────────────────────────────────────────────\n"

        while IFS='|' read -r idx name i_t p_t action type paths o_i o_p; do
            local i_box=" [ ] "; [ "$i_t" -eq 1 ] && i_box=" [✓] "
            local p_box=" [ ] "; [ "$p_t" -eq 1 ] && p_box=" [✓] "

            printf " %-5s %s   %s %-1s %-19s %b%s%b\n" "$idx." "$i_box" "$p_box" "" "$name" "${CYAN}" "$action" "${RESET}"
        done < "$map_file"

        printf " ──────────────────────────────────────────────────────────────\n"
        printf " [A] All   [N] None   [#] Toggle   [C] Confirm   [0] Back   [?] Help\n"
        printf "\n Command: "
        local cmd=$(read_single_char | tr '[:upper:]' '[:lower:]')

        case "$cmd" in
            a|A) 
                # Step 1: Force targets to 1|1 for all rows
                awk -F'|' -v OFS='|' '{$3=1; $4=1; print}' "$map_file" > "${map_file}.tmp"
                
                # Step 2: Re-calculate the "Smart" action text for all 9 columns
                while IFS='|' read -r idx name ti tp act type paths oi op; do
                    new_act=$(get_action_text 1 1 "$oi" "$op")
                    echo "$idx|$name|1|1|$new_act|$type|$paths|$oi|$op"
                done < "${map_file}.tmp" > "$map_file"
                rm -f "${map_file}.tmp"
                ;;
            n|N)
                # Step 1: Force targets to 0|0 for all rows
                awk -F'|' -v OFS='|' '{$3=0; $4=0; print}' "$map_file" > "${map_file}.tmp"
                
                # Step 2: Re-calculate the "Smart" action text for all 9 columns
                while IFS='|' read -r idx name ti tp act type paths oi op; do
                    new_act=$(get_action_text 0 0 "$oi" "$op")
                    echo "$idx|$name|0|0|$new_act|$type|$paths|$oi|$op"
                done < "${map_file}.tmp" > "$map_file"
                rm -f "${map_file}.tmp"
                ;;
            [1-9]*)
                if grep -q "^$cmd|" "$map_file"; then
                    local line=$(grep "^$cmd|" "$map_file")
                    # Extract columns (Note the new positions for Orig_I and Orig_P)
                    local name=$(echo "$line" | cut -d'|' -f2)
                    local cur_i=$(echo "$line" | cut -d'|' -f3)
                    local cur_p=$(echo "$line" | cut -d'|' -f4)
                    local type=$(echo "$line" | cut -d'|' -f6)
                    local paths=$(echo "$line" | cut -d'|' -f7)
                    local o_i=$(echo "$line" | cut -d'|' -f8)
                    local o_p=$(echo "$line" | cut -d'|' -f9)
                    
                    # 3-Way Cycle: (0,0) -> (1,0) -> (1,1) -> Back to (0,0)
                    local next_i=0; local next_p=0
                    if [ "$cur_i" -eq 0 ] && [ "$cur_p" -eq 0 ]; then
                        next_i=1; next_p=0
                    elif [ "$cur_i" -eq 1 ] && [ "$cur_p" -eq 0 ]; then
                        next_i=1; next_p=1
                    else
                        next_i=0; next_p=0
                    fi
                    
                    # Get the smart action text based on the NEW targets vs ORIGINAL live state
                    local next_act=$(get_action_text "$next_i" "$next_p" "$o_i" "$o_p")
                    
                    # Update the map file
                    grep -v "^$cmd|" "$map_file" > "${map_file}.tmp"
                    echo "$cmd|$name|$next_i|$next_p|$next_act|$type|$paths|$o_i|$o_p" >> "${map_file}.tmp"
                    sort -n "${map_file}.tmp" > "$map_file" && rm -f "${map_file}.tmp"
                fi
                ;;
            c)
                # 1. Build Confirmation Lists
                local to_add=""; local to_rem=""
                while IFS='|' read -r idx name t_i t_p action type paths o_i o_p; do
                    # Skip if no change
                    [ "$action" == "No Change" ] && continue

                    # Match specific strings for Additions
                    case "$action" in
                        "> Install Package")
                            to_add="${to_add}\n  + $name (Install)"
                            ;;
                        "> Install + Persist")
                            to_add="${to_add}\n  + $name (Install + Persist)"
                            ;;
                        "> Enable Persistence")
                            to_add="${to_add}\n  + $name (Persist)"
                            ;;
                    esac

                    # Match specific strings for Removals
                    case "$action" in
                        "> Remove Package")
                            to_rem="${to_rem}\n  - $name (Remove)"
                            ;;
                        "> Remove + Unpersist")
                            to_rem="${to_rem}\n  - $name (Remove + Unpersist)"
                            ;;
                        "> Disable Persistence")
                            to_rem="${to_rem}\n  - $name (Unpersist)"
                            ;;
                    esac
                done < "$map_file"

                if [ -z "$to_add" ] && [ -z "$to_rem" ]; then
                    print_error "No changes planned."; sleep 1; continue
                fi

                clear
                print_centered_header "Confirm System Changes"
                [ -n "$to_add" ] && { printf "${GREEN}TO BE INSTALLED or PERSISTED:${RESET}"; printf "$to_add\n\n"; }
                [ -n "$to_rem" ] && { printf "${RED}TO BE REMOVED or UNPERSISTED:${RESET}"; printf "$to_rem\n\n"; }
                
                printf "Proceed with changes? [y/N]: "; read -r confirm; printf "\n"
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    # CRITICAL FIX: Read all 9 columns here!
                    while IFS='|' read -r idx name i_t p_t action type paths o_i o_p; do
                        [ "$action" == "No Change" ] && continue
                        
                        # EXECUTE REMOVALS
                        if [[ "$action" == *"> Remove"* ]] || [[ "$action" == *"> Unpersist"* ]]; then
                            if [ "$i_t" -eq 0 ]; then
                                if [ "$name" == "speedtest" ]; then
                                    rm -f /usr/bin/speedtest
                                else
                                    opkg remove "$name" >/dev/null 2>&1
                                fi
                            fi
                            
                            # Standard cleanup for paths and survival lists
                            for p in $paths; do sed -i "\|$p|d" "$sys_conf" 2>/dev/null; done
                            [ -f "$laz_list" ] && sed -i "\|$name|d" "$laz_list" 2>/dev/null
                        fi

                        # EXECUTE INSTALLS
                        if [[ "$action" == *"Install"* ]] || [[ "$action" == *"Persist"* ]]; then
                            if [ "$i_t" -eq 1 ]; then
                                if [ "$name" == "speedtest" ]; then
                                    install_ookla_speedtest
                                else
                                    [ "$opkg_updated" -eq 0 ] && check_opkg_updated
                                    print_info "Installing $name...\n"
                                    opkg install "$name" >/dev/null 2>&1
                                fi
                            fi

                            if [ "$p_t" -eq 1 ]; then
                                for p in $paths; do grep -qFx "$p" "$sys_conf" || echo "$p" >> "$sys_conf"; done
                                if [ "$type" == "R" ]; then
                                    grep -qFx "$name" "$laz_list" 2>/dev/null || echo "$name" >> "$laz_list"
                                    create_lazarus_hook
                                fi
                            fi
                        fi
                    done < "$map_file"
                    print_success "System changes applied."
                    press_any_key
                    init_system_state
                    continue
                fi
                ;;
            0) rm -f "$map_file" 2>/dev/null; return ;;
            \?|h|H|❓) show_package_help ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

show_ssh_help() {
    clear
    print_centered_header "SSH Key Management - Help"
    
    cat << 'HELPEOF'
SSH Key Management – Quick Help

What is an SSH Key?
───────────────────
An SSH key is a "digital passport" that allows you to log into your router
securely without typing your password every time. It consists of a 
Public Key (which stays on the router) and a Private Key (which stays on 
your computer). 

Main Benefits:
• Security: Keys are virtually impossible to brute-force compared to passwords.
• Convenience: Log in instantly from your terminal or script.
• Persistence: This script can ensure your keys survive firmware updates.

How to find or generate your Public Key:
────────────────────────────────────────
Your Public Key usually ends in .pub. DO NOT paste your Private Key.

• macOS / Linux:
  1. Open Terminal.
  2. Check for existing keys: cat ~/.ssh/id_rsa.pub (or id_ed25519.pub)
  3. To generate new: ssh-keygen -t ed25519
  4. Copy the output of: cat ~/.ssh/id_ed25519.pub

• Windows (PowerShell/CMD):
  1. Open PowerShell.
  2. Check for existing keys: cat $HOME\.ssh\id_rsa.pub
  3. To generate new: ssh-keygen -t ed25519
  4. Copy the text starting with "ssh-ed25519..."

• Windows (PuTTY):
  1. Open 'PuTTYgen'.
  2. Click 'Load' (for existing) or 'Generate' (for new).
  3. Copy the text from the box labeled: 
     "Public key for pasting into OpenSSH authorized_keys file"

Usage in this Menu:
───────────────────
1. Add Key: Paste the entire line (starts with ssh-rsa, ssh-ed25519, etc.).
2. Manage: View existing keys. Use [✓] to mark keys for deletion.
3. Toggle Persistence: Adds /etc/dropbear/authorized_keys to the 
   sysupgrade list so you don't lose access after a firmware update.

Security Warning:
─────────────────
Never share your PRIVATE key with anyone. Only the PUBLIC key belongs
on the router.
HELPEOF
    
    press_any_key
}

manage_ssh_keys() {
    local auth_file="/etc/dropbear/authorized_keys"
    local up_conf="/etc/sysupgrade.conf"
    local ssh_data="/tmp/ssh_mgr.data"

    while true; do
        # 1. Status Calculations
        local key_count=0
        [ -f "$auth_file" ] && key_count=$(grep -c "^ssh-" "$auth_file")
        
        local persistence="${YELLOW}DISABLED${RESET}"
        grep -qFx "$auth_file" "$up_conf" 2>/dev/null && persistence="${GREEN}ENABLED${RESET}"

        clear
        print_centered_header "SSH Key Management"
        
        printf " %b\n" "${CYAN}STATUS${RESET}"
        printf "   Authorized Keys:  %d\n" "$key_count"
        printf "   Persistence:      %b\n\n" "$persistence"

        printf "1️⃣  Add a New SSH Key\n"
        printf "2️⃣  Manage / Delete Keys\n"
        printf "3️⃣  Toggle Persistence\n"
        printf "0️⃣  Return to previous menu\n"
        printf "❓ Show Help\n"
        
        printf "\nChoose [1-3/0/?]: "
        read -r ssh_choice
        
        case "$ssh_choice" in
            1) # ADD KEY
                printf "\n${CYAN}Paste your public key (starts with ssh-rsa, etc.):${RESET}\n"
                read -r new_key
                if echo "$new_key" | grep -qE "^ssh-(rsa|ed25519|dss|ecdsa) "; then
                    # Extract base64 part for duplicate check
                    local key_base64=$(echo "$new_key" | awk '{print $2}')
                    if [ -f "$auth_file" ] && grep -q "$key_base64" "$auth_file"; then
                        print_warning "Key already exists in authorized_keys."
                    else
                        mkdir -p /etc/dropbear
                        echo "$new_key" >> "$auth_file"
                        chmod 0700 /etc/dropbear && chmod 0600 "$auth_file"
                        print_success "Key added successfully."
                    fi
                else
                    print_error "Invalid key format."
                fi
                press_any_key ;;

            2) # MANAGE / DELETE UI
                if [ ! -s "$auth_file" ]; then
                    print_error "No keys found to manage."
                    sleep 1; continue
                fi

                while true; do
                    # Generate fresh temp data: Index | Type | Identity | Selected(0/1)
                    # Use awk to handle keys with no comments by truncating the key string itself
                    awk '{
                        type=$1; 
                        # If comment (field 3) exists, use it. Otherwise, truncate field 2.
                        if ($3 != "") { 
                            id=$3; for(i=4;i<=NF;i++) id=id" "$i 
                        } else { 
                            id="(No comment) " substr($2,1,15)"..." 
                        }
                        print NR "|" type "|" id "|0"
                    }' "$auth_file" > "$ssh_data"

                    while true; do
                        clear
                        print_centered_header "SSH Authorized Keys Manager"
                        printf "\n"
                        printf " %-5s %-4s %-12s %-30s\n" "Sel" "Idx" "Key Type" "Identity / Comment"
                        printf " ──────────────────────────────────────────────────────────────\n"
                        while IFS='|' read -r idx type id sel; do
                            s_box="[ ]"; [ "$sel" -eq 1 ] && s_box="[✓]"
                            printf " %s %-1s %-4s %-12s %-40s\n" "$s_box" "" "$idx." "$type" "$id"
                        done < "$ssh_data"
                        printf " ──────────────────────────────────────────────────────────────\n"
                        printf " [A] All   [N] None   [#] Toggle   [D] Delete   [0] Back\n"
                        printf " Command: "
                        read -r cmd

                        case "$cmd" in
                            a|A) sed -i 's/|0$/|1/' "$ssh_data" ;;
                            n|N) sed -i 's/|1$/|0/' "$ssh_data" ;;
                            [0-9]*)
                                [ "$cmd" -eq 0 ] && break 2
                                awk -F'|' -v t="$cmd" 'BEGIN{OFS="|"} {if($1==t) $4=($4==1?0:1); print}' "$ssh_data" > "$ssh_data.tmp" && mv "$ssh_data.tmp" "$ssh_data" ;;
                            d|D)
                                local to_del=$(awk -F'|' '$4==1' "$ssh_data")
                                if [ -z "$to_del" ]; then
                                    print_warning "No keys selected."; sleep 1; continue
                                fi
                                
                                clear
                                print_centered_header "Confirm Deletion"
                                echo "$to_del" | awk -F'|' '{print "  - " $2 " (" $3 ")"}'
                                printf "\nDelete selected keys? [y/N]: "; read -r confirm
                                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                                    # Create a keep-list of line numbers
                                    local lines_to_keep=$(awk -F'|' '$4==0 {print $1}' "$ssh_data")
                                    if [ -z "$lines_to_keep" ]; then
                                        > "$auth_file" # Wipe if all deleted
                                    else
                                        # Use awk to reconstruct the file from original line numbers
                                        local tmp_auth="/tmp/auth.keep"
                                        for l in $lines_to_keep; do
                                            sed -n "${l}p" "$auth_file" >> "$tmp_auth"
                                        done
                                        mv "$tmp_auth" "$auth_file"
                                    fi
                                    chmod 0600 "$auth_file"
                                    print_success "Keys updated."
                                    break 2
                                fi ;;
                            0) break 2 ;;
                        esac
                    done
                done
                rm -f "$ssh_data" ;;

            3) # TOGGLE PERSISTENCE
                printf "\n"
                if grep -qFx "$auth_file" "$up_conf" 2>/dev/null; then
                    sed -i "\|$auth_file|d" "$up_conf"
                    print_warning "Persistence disabled. Keys will be lost on firmware upgrade."
                else
                    echo "$auth_file" >> "$up_conf"
                    print_success "Persistence enabled. Keys will survive firmware upgrades."
                fi
                press_any_key ;;
                
            0) return ;;
            \?|h|H|❓) show_ssh_help ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

system_tweaks() {
    while true; do
        clear
        print_centered_header "System Tweaks"
        printf "1️⃣  Device Fan Settings\n"
        printf "2️⃣  Manage Zram Swap\n"
        printf "3️⃣  Package and Persistence Manager\n"
        printf "4️⃣  SSH Key Management\n"
        printf "0️⃣  Main menu\n"
        printf "❓ Help\n"
        printf "\nChoose [1-4/0/?]: "
        read -r st_choice
        printf "\n"
        case $st_choice in
            1) manage_fan_settings ;;
            2) manage_zram ;;
            3) manage_packages ;;
            4) manage_ssh_keys ;;
            \?|h|H|❓) show_system_tweaks_help ;;
            0) return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# -----------------------------
# System Benchmarks
# -----------------------------

show_librespeed_help() {
    clear
    print_centered_header "LibreSpeed SpeedTest - Help"
    
    cat << 'HELPEOF'
LibreSpeed SpeedTest Server – Quick Help

What is LibreSpeed?
───────────────────
LibreSpeed is a lightweight, open-source speed test server written in Go. Unlike 
traditional speed tests that rely on external servers, this runs locally on your 
router. This allows you to test the actual throughput of your LAN and Wi-Fi 
without being limited by your ISP's internet speed.

Main features on GL.iNet routers:
• Zero Dependencies: Standalone Go binary; does not require Nginx or PHP.
• Lightweight: Extremely low CPU and RAM footprint, ideal for travel routers.
• Privacy Focused: No telemetry, no ads, and no data collection.
• Local Benchmarking: Perfect for testing Wi-Fi 6/7 performance and signal dead zones.

LibreSpeed vs. OpenSpeedTest:
─────────────────────────────
• LibreSpeed: Best for background monitoring and 1Gbps wireless audits. 
  It is much lighter on system resources (RAM/CPU).
• OpenSpeedTest: Better for high-stress 2.5G/10G throughput testing on 
  powerful hardware (like the Flint 2/3) due to its multi-threaded nature.
• Better Together: Both can run simultaneously on different ports (e.g., 8989 
  and 8888) to allow A/B testing of your wireless environment.

When should you use it?
Yes → To find Wi-Fi dead zones or verify the max speed of your local network.
Yes → To check if your VPN or SQM settings are bottlenecking your local speeds.
No  → If you only care about your ISP's "Internet" speed (use Ookla for that).

Important notes:
• Listen Port: Defaults to :8989. Access via http://<router-ip>:8989
• Persistence: Enabling persistence ensures the binary and settings survive 
  firmware updates, preventing manual re-installation.
• Procd Jail: Runs in a secure sandbox for improved router security.
HELPEOF
    
    press_any_key
}

manage_librespeed() {
    while true; do
        clear
        print_centered_header "LibreSpeed SpeedTest Management"
        
        LAN_IP=$(uci -q get network.lan.ipaddr || echo "192.168.8.1")
        LISTEN_PORT=":8989"
        UP_CONF="/etc/sysupgrade.conf"
        
        # Determine installation status once for the whole loop
        if command -v librespeed-go >/dev/null 2>&1; then
            IS_INSTALLED=1
        else
            IS_INSTALLED=0
        fi

        printf " %b\n" "${CYAN}STATUS${RESET}"
        if [ "$IS_INSTALLED" -eq 1 ]; then
            if [ "$(uci -q get librespeed-go.config.enabled)" = "1" ]; then
                printf "   Service: %bENABLED%b\n" "${GREEN}" "${RESET}"
                if netstat -ltn 2>/dev/null | grep -q "${LISTEN_PORT#:}"; then
                    printf "   Status: %bACTIVE%b\n" "${GREEN}" "${RESET}"
                    printf "   URL: %bhttp://$LAN_IP${LISTEN_PORT}%b\n" "${CYAN}" "${RESET}"
                else
                    printf "   Status: %bSTARTING/ERROR%b\n" "${YELLOW}" "${RESET}"
                fi
            else
                printf "   Service: %bDISABLED%b\n" "${YELLOW}" "${RESET}"
            fi
            
            # Check Persistence Status
            persist_ok="1"
            for entry in "/usr/bin/librespeed-go" "/etc/init.d/librespeed-go" "/etc/config/librespeed-go"; do
                if ! grep -qFx "$entry" "$UP_CONF" 2>/dev/null; then
                    persist_ok="0"
                    break
                fi
            done
            
            if [ "$persist_ok" -eq "1" ]; then
                printf "   Persistence: %bENABLED%b\n" "${GREEN}" "${RESET}"
            else
                printf "   Persistence: %bDISABLED%b\n" "${RED}" "${RESET}"
            fi
        else
            printf "   Service: %bNOT INSTALLED%b\n" "${RED}" "${RESET}"
        fi
        
        printf "\n1️⃣  Install and Enable\n"
        printf "2️⃣  Disable Service\n"
        printf "3️⃣  Toggle Persistence\n"
        printf "4️⃣  Uninstall Package\n"
        printf "0️⃣  Main menu\n"
        printf "❓ Help\n"
        printf "\nChoose [1-4/0/?]: "
        read -r ls_choice
        printf "\n"
        
        case $ls_choice in
            1)
                if [ "$IS_INSTALLED" -eq 0 ]; then
                    print_warning "Installing LibreSpeed...\n"
                    check_opkg_updated
                    opkg install librespeed-go >/dev/null 2>&1
                    grep -q "librespeed" /etc/passwd || echo "librespeed:x:500:500:librespeed:/var/run/librespeed-go:/bin/false" >> /etc/passwd
                    IS_INSTALLED=1
                fi

                if [ ! -f "/etc/config/librespeed-go" ]; then
                    touch /etc/config/librespeed-go
                fi
                
                if ! uci -q get librespeed-go.config >/dev/null; then
                    uci set librespeed-go.config=librespeed-go
                fi

                uci set librespeed-go.config.listen_addr="$LISTEN_PORT"
                uci set librespeed-go.config.enabled='1'
                uci commit librespeed-go
                
                /etc/init.d/librespeed-go restart >/dev/null 2>&1
                print_success "LibreSpeed enabled at http://$LAN_IP${LISTEN_PORT}"
                press_any_key
                ;;
            2)
                if [ "$IS_INSTALLED" -eq 1 ]; then
                    uci set librespeed-go.config.enabled='0'
                    uci commit librespeed-go
                    /etc/init.d/librespeed-go stop >/dev/null 2>&1
                    print_success "LibreSpeed disabled"
                else
                    print_error "Nothing to disable: LibreSpeed is not installed."
                fi
                press_any_key
                ;;
            3)
                if [ "$IS_INSTALLED" -eq 1 ]; then
                    if [ "$persist_ok" -eq "0" ]; then
                        for entry in "/usr/bin/librespeed-go" "/etc/init.d/librespeed-go" "/etc/config/librespeed-go"; do
                            grep -qFx "$entry" "$UP_CONF" || echo "$entry" >> "$UP_CONF"
                        done
                        print_success "Persistence enabled in $UP_CONF"
                    else
                        sed -i "\|/usr/bin/librespeed-go|d" "$UP_CONF"
                        sed -i "\|/etc/init.d/librespeed-go|d" "$UP_CONF"
                        sed -i "\|/etc/config/librespeed-go|d" "$UP_CONF"
                        print_success "Persistence disabled"
                    fi
                else
                    print_error "Nothing to persist: LibreSpeed is not installed."
                fi
                press_any_key
                ;;
            4)
                if [ "$IS_INSTALLED" -eq 1 ]; then
                    printf "%b" "${YELLOW}Remove LibreSpeed package? [y/N]: ${RESET}"; read -r confirm
                    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                        /etc/init.d/librespeed-go stop >/dev/null 2>&1
                        opkg remove librespeed-go >/dev/null 2>&1
                        # Always clean up persistence entries on uninstall
                        sed -i "\|/usr/bin/librespeed-go|d" "$UP_CONF"
                        sed -i "\|/etc/init.d/librespeed-go|d" "$UP_CONF"
                        sed -i "\|/etc/config/librespeed-go|d" "$UP_CONF"
                        print_success "LibreSpeed removed"
                    fi
                else
                    print_error "Nothing to remove: LibreSpeed is not installed."
                fi
                press_any_key
                ;;
            0) return ;;
            \?|h|H|❓) show_librespeed_help ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

install_ookla_speedtest() {
    if ! command -v speedtest >/dev/null 2>&1 || ! speedtest --version 2>&1 | grep -qi "ookla"; then
        print_warning "Ookla Speedtest not found, installing..."
        arch=$(uname -m)
        case "$arch" in
            aarch64) suffix="aarch64" ;;
            armv7*)  suffix="armhf"   ;;
            armv8*)  suffix="aarch64" ;;
            mips*)   suffix="mips"    ;;
            x86_64)  suffix="x86_64"  ;;
            *) print_error "Unsupported Arch: $arch"; continue ;;
        esac
        ver=$(wget -qO- https://www.speedtest.net/apps/cli | grep -oE "ookla-speedtest-[0-9.]+-linux-$suffix.tgz" | head -n1)
        [ -z "$ver" ] && ver="ookla-speedtest-1.2.0-linux-$suffix.tgz"
        if [ -n "$ver" ]; then
            url="https://install.speedtest.net/app/cli/$ver"
            wget -qO- "$url" | tar xz -C /usr/bin speedtest 2>/dev/null
            chmod +x /usr/bin/speedtest 2>/dev/null
            print_success "Installed: $(speedtest --version | head -n1)"
        else
            print_error "Could not find download link for $suffix"
            press_any_key
            continue
        fi
        if ! command -v speedtest >/dev/null 2>&1; then
            print_error "Failed to install Ookla Speedtest"
            press_any_key
            continue
        fi
    fi
}

benchmark_system() {
    while true; do
        clear
        print_centered_header "System Benchmarks"
        printf "1️⃣  CPU Thermal Stress Test\n"
        printf "2️⃣  CPU Benchmark (OpenSSL)\n"
        printf "3️⃣  Disk I/O Benchmark\n"
        printf "4️⃣  Memory I/O Benchmark\n"
        printf "5️⃣  DNS Latency Benchmark\n"
        printf "6️⃣  Ookla Internet SpeedTest\n"
        printf "7️⃣  LibreSpeed SpeedTest Server\n"
        printf "8️⃣  OpenSpeedTest Server\n"
        printf "0️⃣  Main menu\n"
        printf "\nChoose [1-8/0]: "
        read -r bench_choice
        printf "\n"
        
        case $bench_choice in
            1)
                clear
                print_centered_header "CPU Thermal Stress Test"
                
                if ! command -v stress >/dev/null 2>&1; then
                    print_warning "stress not found, installing..."
                    check_opkg_updated
                    opkg install stress >/dev/null 2>&1
                    if ! command -v stress >/dev/null 2>&1; then
                        opkg install stress-ng >/dev/null 2>&1
                        if ! command -v stress-ng >/dev/null 2>&1; then
                            print_error "Failed to install stress"
                            press_any_key
                            continue
                        else 
                            ln -s "$(which stress-ng)" /usr/bin/stress
                        fi
                    fi
                fi

                get_temp() {
                    local raw_temp
                    raw_temp=$(get_cpu_temp)
                    if [ "$raw_temp" != "unknown" ]; then
                        local celsius=$(awk "BEGIN {printf \"%.2f\", $raw_temp}")
                        local fahrenheit=$(awk "BEGIN {printf \"%.2f\", ($raw_temp * 1.8) + 32}")
                        printf "%s°C (%s°F)" "$celsius" "$fahrenheit"
                    else
                        printf "N/A"
                    fi
                }
                
                cpu_cores=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null)
                [ -z "$cpu_cores" ] && cpu_cores=1
                
                printf "\nHow many seconds to run stress test? [default: 60]: "
                read -r duration
                [ -z "$duration" ] && duration=60
                
                case "$duration" in
                    ''|*[!0-9]*) duration=60 ;;
                esac

                raw_start=$(get_cpu_temp)
                start_temp_str=$(get_temp)
                start_fan_str=$(get_fan_speed)
                
                printf "\n%b\n" "${YELLOW}⏳ Running stress test on $cpu_cores cores for $duration seconds...${RESET}"
                                
                stress --cpu "$cpu_cores" --timeout "${duration}s"

                raw_end=$(get_cpu_temp)
                end_temp_str=$(get_temp)
                end_fan_str=$(get_fan_speed)
                usleep 3000000
                raw_post=$(get_cpu_temp)
                post_temp_str=$(get_temp)
                post_fan_str=$(get_fan_speed)
                
                printf "\n"
                print_success "Stress test completed\n"
                if [ "$raw_start" != "unknown" ] && [ "$raw_end" != "unknown" ]; then
                    diff_c=$(awk "BEGIN {printf \"%+.2f\", $raw_end - $raw_start}")
                    diff_f=$(awk "BEGIN {printf \"%+.1f\", ($raw_end - $raw_start) * 1.8}")
                    post_diff_c=$(awk "BEGIN {printf \"%+.2f\", $raw_post - $raw_start}")
                    post_diff_f=$(awk "BEGIN {printf \"%+.1f\", ($raw_post - $raw_start) * 1.8}")
                    
                    # Fan % Changes
                    if [ "$start_fan_str" = "N/A" ] || [ "$start_fan_str" -eq 0 ] 2>/dev/null; then
                        fan_p="+0.0"
                        fan_post_p="+0.0"
                    else
                        fan_p=$(awk "BEGIN {printf \"%+.1f\", (($end_fan_str - $start_fan_str) / $start_fan_str) * 100}")
                        fan_post_p=$(awk "BEGIN {printf \"%+.1f\", (($post_fan_str - $start_fan_str) / $start_fan_str) * 100}")
                    fi

                    # --- TABLE RENDER ---
                    printf "     %-16s %-22s %-16s %-15s\n" "PHASE" "TEMPERATURE" "Δ CHANGE" "FAN SPEED (Δ%)"
                    printf "────────────────   ──────────────────   ──────────────────   ────────────────────\n"
                    printf "%-18s %-30s %-12s %-12s\n" "Start" "$start_temp_str" "---" "$start_fan_str RPM"
                    printf "%-18s %-22s %-8s %-13s %-4s %-12s\n" "End" "$end_temp_str" "$diff_c°C" "($diff_f°F)" "$end_fan_str RPM" "($fan_p%)"
                    printf "%-18s %-22s %-8s %-13s %-4s %-12s\n" "End + 3s" "$post_temp_str" "$post_diff_c°C" "($post_diff_f°F)" "$post_fan_str RPM" "($fan_post_p%)"
                fi         
                press_any_key
                ;;
            2)
                clear
                print_centered_header "OpenSSL CPU Benchmark"

                if ! command -v openssl >/dev/null 2>&1; then
                    print_error "OpenSSL not found"
                    press_any_key
                    continue
                fi
                
                # --- MT7987a - Beryl 7 Baselines (k bytes/s) ---
                BASE_AES="93653 269054 508791 660796 718897 721709"
                BASE_SHA="70723 214609 497956 740733 866776 876396"
                
                # RSA Baselines (sign/s and verify/s)
                BASE_RSA_S=180.9; BASE_RSA_V=6765.6
                BASE_RSA_MS=715.8; BASE_RSA_MV=26528.0

                print_info "Running OpenSSL speed benchmark. This will take a minute...\n"
                
                # --- Function to Print Aligned Delta Row ---
                # Usage: print_delta "type_string" "baseline_string" "raw_output_file"
                print_delta() {
                    local type=$1; local baseline=$2; local datafile=$3
                    printf "${YELLOW}%-16s${RESET}" "% Δ Beryl 7:"
                    # Use awk to handle case-insensitivity and matching
                    awk -v t="$type" -v base="$baseline" -v r="$RED" -v g="$GREEN" -v res="$RESET" '
                    # Convert first column to lowercase to match our "type" variable
                    tolower($1) == tolower(t) {
                        split(base, b_arr);
                        for(i=1; i<=6; i++) {
                            cur = $(i+1); gsub(/k/, "", cur);
                            # If OpenSSL output is 0.00, avoid division by zero
                            if (b_arr[i] > 0) {
                                diff = ((cur - b_arr[i]) / b_arr[i]) * 100;
                                printf "%s%10.1f%%%s  ", (diff >= 0 ? g : r), diff, res
                            }
                        }
                    }' "$datafile"
                    echo ""
                }

                # --- AES Section ---
                printf "%b\n" "${CYAN}Single-threaded AES-256-GCM:${RESET}"
                openssl speed -elapsed -evp aes-256-gcm 2>&1 | tee /tmp/ssl_res | tail -n 3
                print_delta "aes-256-gcm" "$BASE_AES" "/tmp/ssl_res"

                # --- SHA Section ---
                printf "\n%b\n" "${CYAN}Single-threaded SHA256:${RESET}"
                openssl speed -elapsed sha256 2>&1 | tee /tmp/ssl_res | tail -n 3
                print_delta "sha256" "$BASE_SHA" "/tmp/ssl_res"

                # --- RSA Section (Helper for RSA logic) ---
                process_rsa() {
                    local label=$1; local cmd=$2; local b_sign=$3; local b_verify=$4
                    printf "\n%b\n" "${CYAN}$label:${RESET}"
                    $cmd > /tmp/ssl_res 2>/dev/null
                    grep -E '^ {10}|^rsa' /tmp/ssl_res
                    
                    # Parse sign/s (col 6) and verify/s (col 7)
                    read cur_s cur_v <<EOF
            $(grep "^rsa 2048" /tmp/ssl_res | awk '{print $6, $7}')
EOF
                    # Calculate Deltas inside awk to avoid bc dependency
                    awk -v cs="$cur_s" -v bs="$b_sign" -v cv="$cur_v" -v bv="$b_verify" \
                        -v r="$RED" -v g="$GREEN" -v res="$RESET" -v y="$YELLOW" 'BEGIN {
                        ds = ((cs - bs) / bs) * 100; dv = ((cv - bv) / bv) * 100;
                        printf "%s%% Δ Beryl 7:  %s%+.1f%% (Sign)%s  /  %s%+.1f%% (Verify)%s\n", 
                            y, (ds>=0?g:r), ds, res, (dv>=0?g:r), dv, res
                    }'
                }

                process_rsa "RSA 2048-bit signing" "openssl speed -elapsed rsa2048" "$BASE_RSA_S" "$BASE_RSA_V"

                cores=$(grep -c ^processor /proc/cpuinfo)
                if [ "$cores" -gt 1 ]; then
                    process_rsa "RSA 2048-bit (Multi-core - $cores cores)" "openssl speed -elapsed -multi $cores rsa2048" "$BASE_RSA_MS" "$BASE_RSA_MV"
                fi

                rm -f /tmp/ssl_res
                printf "\n"
                print_success "Benchmark completed"
                press_any_key
                ;;
            3)
                clear
                print_centered_header "Disk I/O Benchmark"
                
                # --- Beryl 7 (MT7981) Baselines (MB/s) ---
                BASE_W=119.05
                BASE_R=10.62

                available_kb=$(df -Pk . | awk 'NR==2 {print $4}')
                
                # Check for space (Using your established test_size logic)
                if [ "$available_kb" -ge 1024000 ]; then test_size=1000; test_name="1GB"
                elif [ "$available_kb" -ge 512000 ]; then test_size=500; test_name="500MB"
                elif [ "$available_kb" -ge 256000 ]; then test_size=250; test_name="250MB"
                elif [ "$available_kb" -ge 128000 ]; then test_size=125; test_name="125MB"
                elif [ "$available_kb" -ge 64000 ]; then test_size=64; test_name="64MB"
                elif [ "$available_kb" -ge 32000 ]; then test_size=32; test_name="32MB"
                else test_size=16; test_name="16MB"; fi
                
                printf "Test size: %b%s%b\n" "${GREEN}" "$test_name" "${RESET}"
                
                # Helper for ms timing
                get_ms() { read ut _ < /proc/uptime; awk -v t="$ut" 'BEGIN {print int(t * 1000)}'; }

                # --- Write Test ---
                printf "\n%b\n" "${YELLOW}⏳ Running write test ($test_name)...${RESET}"
                sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
                
                w_start=$(get_ms)
                dd if=/dev/zero of=./testfile bs=1M count=$test_size conv=fsync 2>&1 | tail -n 1
                w_end=$(get_ms)
                
                # --- Read Test ---
                printf "%b\n" "${YELLOW}⏳ Running read test ($test_name)...${RESET}"
                sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
                
                r_start=$(get_ms)
                dd if=./testfile of=/dev/null bs=1M 2>&1 | tail -n 1
                r_end=$(get_ms)
                
                # --- UI Reporting (The SSL Style) ---
                printf "\n%b%s Results:%b\n\n" "${CYAN}" "$test_name" "${RESET}"
                printf "     %-14s  %-15s  %-16s\n" "TYPE" "SPEED" "% Δ BERYL 7"
                printf "──────────────   ──────────────   ────────────────────\n"
                
                # Use awk to process both results for precision and delta alignment
                awk -v ws="$w_start" -v we="$w_end" -v rs="$r_start" -v re="$r_end" \
                    -v sz="$test_size" -v bw="$BASE_W" -v br="$BASE_R" \
                    -v r="$RED" -v g="$GREEN" -v y="$YELLOW" -v res="$RESET" '
                BEGIN {
                    # Write Math
                    w_ms = we - ws; if(w_ms <= 0) w_ms = 1;
                    w_spd = (sz * 1000) / w_ms;
                    w_diff = ((w_spd - bw) / bw) * 100;

                    # Read Math
                    r_ms = re - rs; if(r_ms <= 0) r_ms = 1;
                    r_spd = (sz * 1000) / r_ms;
                    r_diff = ((r_spd - br) / br) * 100;

                    # Output Rows
                    printf "Write (Sync)     %-16s %s%+.1f%%%s (%s MB/s)\n", sprintf("%.2f MB/s", w_spd), (w_diff>=0?g:r), w_diff, res, bw;
                    printf "Read (Cached)    %-16s %s%+.1f%%%s (%s MB/s)\n", sprintf("%.2f MB/s", r_spd), (r_diff>=0?g:r), r_diff, res, br;
                }'

                rm -f ./testfile
                printf "\n"
                print_success "Disk benchmark completed"
                press_any_key
                ;;
            4)
                clear
                print_centered_header "Memory I/O Benchmark"
                
                # --- Beryl 7 (MT7981) Memory Baseline (MB/s) ---
                # Based on internal DDR bandwidth tests
                BASE_MEM=4351.61

                if [ -f /proc/meminfo ]; then
                    total_mem=$(awk '/MemTotal/ {
                        m = $2 / 1024
                        est = m + 30
                        rounded = (int((est + 127) / 128) * 128)
                        print rounded
                    }' /proc/meminfo)
                fi
                
                total_mem=${total_mem:-512} # Default to 512MB if we can't read it

                # Determine test size (100k blocks of 1M = 100GB of throughput)
                # We want a large enough test to bypass L1/L2 cache saturation
                if [ "$total_mem" -ge 960 ]; then test_size=100000; test_name="100GB"
                elif [ "$total_mem" -ge 460 ]; then test_size=50000; test_name="50GB"
                else test_size=25000; test_name="25GB"; fi
                
                printf "System RAM: %b%s MB%b\n" "${GREEN}" "$total_mem" "${RESET}"
                printf "Test throughput: %b%s%b\n" "${GREEN}" "$test_name" "${RESET}"
                
                # Helper for ms timing
                get_ms() { read ut _ < /proc/uptime; awk -v t="$ut" 'BEGIN {print int(t * 1000)}'; }

                printf "\n%b\n" "${YELLOW}⏳ Measuring Memory Controller Throughput...${RESET}"
                
                m_start=$(get_ms)
                # We use a large block size (1M) to maximize throughput
                dd if=/dev/zero of=/dev/null bs=1M count=$test_size 2>&1 | tail -n 1
                m_end=$(get_ms)
                
                # --- UI Reporting (The Unified Style) ---
                printf "\n%bMemory Performance Results:%b\n\n" "${CYAN}" "${RESET}"
                printf "     %-14s  %-15s  %-16s\n" "TYPE" "SPEED" "% Δ BERYL 7"
                printf "──────────────   ──────────────   ────────────────────\n"
                
                awk -v ms_s="$m_start" -v ms_e="$m_end" -v sz="$test_size" -v base="$BASE_MEM" \
                    -v r="$RED" -v g="$GREEN" -v res="$RESET" '
                BEGIN {
                    total_ms = ms_e - ms_s; if(total_ms <= 0) total_ms = 1;
                    speed = (sz * 1000) / total_ms;
                    diff = ((speed - base) / base) * 100;

                    printf "Read / Write     %-16s %s%+.1f%%%s (%s MB/s)\n", 
                        sprintf("%.2f MB/s", speed), (diff>=0?g:r), diff, res, base;
                }'

                printf "\n"
                print_success "Memory benchmark completed"
                press_any_key
                ;;
            5)
                clear
                print_centered_header "DNS Benchmark"

                print_info "Starting Comprehensive DNS Benchmark...\n"
                
                # Pre-check: Can we resolve anything at all?
                if ! nslookup google.com >/dev/null 2>&1; then
                    print_error "DNS is not responding. Check your internet connection or DNS settings."
                    press_any_key
                    continue
                fi

                # Check for Hijacking
                is_proxied=0
                if nslookup "detect${RANDOM}.com" 1.2.3.4 >/dev/null 2>&1; then
                    is_proxied=1
                    print_warning "DNS Interception Active: Traffic is being redirected locally.\n"
                fi
                
                # Servers to test
                SERVERS="127.0.0.1 1.1.1.1 8.8.8.8 9.9.9.9"
                SAMPLES=20  # Number of tests per server
                
                printf "     %-19s %-8s %-10s %-8s\n" "DNS Server" "Min" "Avg" "Max"
                printf "─────────────────────  ───────  ───────  ───────────\n"

                for server in $SERVERS; do
                    case $server in
                        "127.0.0.1") label="Local (AdGuard/Cache)" ;;
                        "1.1.1.1")   label="Cloudflare" ;;
                        "8.8.8.8")   label="Google" ;;
                        "9.9.9.9")   label="Quad9" ;;
                    esac

                    total=0; min=9999; max=0; BURST=5

                    for i in $(seq 1 10); do
                        test_domain="bench${RANDOM}.net"

                        read ut _ < /proc/uptime
                        start_t=$ut
                        
                        # Execute a burst of lookups to exceed the 10ms clock tick
                        for b in $(seq 1 $BURST); do
                            nslookup "$test_domain" "$server" >/dev/null 2>&1
                        done
                        
                        read ut _ < /proc/uptime
                        end_t=$ut
                        
                        # Calculate per-query msec: ((end - start) * 1000) / BURST
                        msec=$(awk -v s="$start_t" -v e="$end_t" -v b="$BURST" \
                              'BEGIN { printf "%.2f", ((e - s) * 1000) / b }')

                        # Update stats
                        min=$(awk -v m="$msec" -v cur="$min" 'BEGIN { print (m < cur ? m : cur) }')
                        max=$(awk -v m="$msec" -v cur="$max" 'BEGIN { print (m > cur ? m : cur) }')
                        total=$(awk -v m="$msec" -v t="$total" 'BEGIN { print t + m }')
                    done

                    avg=$(awk -v t="$total" 'BEGIN { printf "%.2f", t / 10 }')

                    COLOR=$CYAN
                    if [ $(awk -v a="$avg" 'BEGIN {print (a < 15.0 ? 1 : 0)}') -eq 1 ]; then 
                        COLOR=$GREEN
                    fi
                        
                    printf "%-22s %b%-8s %-8s %-8s%b ms\n" "$label" "$COLOR" "$min" "$avg" "$max" "$RESET"
                done
                
                printf "\n"
                print_success "DNS Benchmark completed"
                press_any_key
                ;;
            6)
                clear
                print_centered_header "Ookla Network SpeedTest"
                install_ookla_speedtest
                
                printf "\n%b\n" "${YELLOW}⏳ Running Ookla SpeedTest...${RESET}"
                printf "──────────────────────────────────────────────────────────────────────\n"

                speedtest -a --accept-license --accept-gdpr 2>/dev/null
                
                printf "\n──────────────────────────────────────────────────────────────────────\n"
                print_success "Ookla SpeedTest completed"         
                press_any_key
                ;;
            7)  manage_librespeed ;;
            8)  install_openspeedtest ;;
            0)
                return
                ;;
            *) print_error "Invalid option"; sleep 1 ;;
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
            0)
                return
                ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

install_openspeedtest() {
    local script_url="https://raw.githubusercontent.com/phantasm22/OpenSpeedTestServer/main/install_openspeedtest.sh"
    local script_name="install_openspeedtest.sh"
    local expected_header="Author: phantasm22"

    clear
    print_centered_header "OpenSpeedTest Server Installation"

    # Check if we need to download (file missing OR invalid header)
    if [ ! -f "$script_name" ] || ! grep -q "$expected_header" "$script_name"; then
        print_info "Downloading latest OpenSpeedTest installer..."
        
        if wget -q -O "$script_name" "$script_url" && [ -s "$script_name" ]; then
            chmod +x "$script_name"
            print_success "Download successful."
        else
            print_error "Failed to download installer. Please check your connection."
            rm -f "$script_name"
            press_any_key
            return 1
        fi
    fi

    # Execute the script
    print_info "Launching installer...\n"
    sleep 2
    
    # Check for execution bit just in case
    [ ! -x "$script_name" ] && chmod +x "$script_name"
    
    ./"$script_name"
    
    # Handle post-execution status
    if [ $? -eq 0 ]; then
        print_success "OpenSpeedTest setup sequence finished."
    else
        print_warning "Installer exited with a non-zero status."
    fi

    press_any_key
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
        printf "\n"
        print_warning "Recovery failed or cancelled. AdGuardHome features will be disabled.\n"
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
        printf "3️⃣  System Tweaks\n"
        printf "4️⃣  System Benchmarks\n"
        printf "5️⃣  View System Configuration (UCI)\n"
        printf "6️⃣  Check for Update\n"
        printf "0️⃣  Exit\n"
        printf "\nChoose [1-6/0]: "
        read opt
        
        case $opt in
            1) show_hardware_info ;;
            2) [ $AGH_DISABLED != 1 ] && agh_control_center || { print_error "AGH not found. Feature disabled."; sleep 2; } ;;
            3) system_tweaks ;;
            4) benchmark_system ;;
            5) view_uci_config ;;
            6) check_self_update "$@"; press_any_key ;;
            0) clear; printf "\n"; print_success "Thanks for using GL.iNet Toolkit!\n"; exit 0 ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# -----------------------------
# Start
# -----------------------------
show_menu
