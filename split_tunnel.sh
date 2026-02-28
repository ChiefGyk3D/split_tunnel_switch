#!/bin/bash
# NetworkManager Split Tunnel Script
# For automatic switching, place in /etc/NetworkManager/dispatcher.d/99-split-tunnel
# Version: 3.0.0
#
# Copyright (C) 2025-2026 ChiefGyk3D
# License: GPL-3.0-or-later
#
# Features:
#   - Safe config parsing (no eval/source of untrusted input)
#   - IPv4 and IPv6 dual-stack support
#   - DNS leak prevention via per-interface DNS routing
#   - Bypass mode (default) and Include mode (route only listed subnets through VPN)
#   - Multiple VPN interface support
#   - Route metrics / priority control
#   - Connectivity verification after route changes
#   - Automatic local subnet discovery
#   - Kill switch (block non-VPN traffic except bypass subnets)
#   - Route persistence via systemd timer
#   - Log rotation support
#   - Verbose / debug output
#   - Config validation command
#   - Desktop notifications (optional)
#   - Configurable vpn-down route cleanup

set -euo pipefail

# ============================================================================
# CONSTANTS
# ============================================================================
readonly VERSION="3.0.0"
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
CONFIG_FILE="${SPLIT_TUNNEL_CONFIG:-/etc/split_tunnel/split_tunnel.conf}"
readonly DEFAULT_LOG_FILE="/var/log/split_tunnel.log"
readonly DEFAULT_LOCK_FILE="/var/run/split_tunnel.lock"
readonly IPTABLES_CHAIN="SPLIT_TUNNEL_KS"
readonly IP6TABLES_CHAIN="SPLIT_TUNNEL_KS"
readonly NFTABLES_TABLE="split_tunnel_killswitch"

# ============================================================================
# DEFAULT SETTINGS (overridden by config file)
# ============================================================================
# --- Subnets ---
BYPASS_SUBNETS=("192.168.1.0/24" "192.168.2.0/24")
BYPASS_SUBNETS_V6=()

# --- Mode ---
# "bypass"  = listed subnets skip VPN (default, original behavior)
# "include" = ONLY listed subnets go through VPN; everything else is direct
TUNNEL_MODE="bypass"

# --- VPN interfaces (array for multi-VPN support) ---
VPN_INTERFACES=("tun0")

# --- Logging ---
ENABLE_LOGGING="true"
LOG_FILE="$DEFAULT_LOG_FILE"
VERBOSE="false"

# --- Behavior ---
DRY_RUN="false"
LOCK_FILE="$DEFAULT_LOCK_FILE"

# --- Route metrics ---
ROUTE_METRIC=""

# --- Connectivity verification ---
VERIFY_CONNECTIVITY="false"
VERIFY_HOSTS=()

# --- Auto-discover local subnets ---
AUTO_DISCOVER_SUBNETS="false"

# --- Kill switch ---
KILL_SWITCH="false"
KILL_SWITCH_BACKEND="iptables"   # "iptables" or "nftables"

# --- DNS leak prevention ---
DNS_LEAK_PREVENTION="false"
DIRECT_DNS_SERVERS=()

# --- vpn-down behavior ---
REMOVE_ROUTES_ON_VPN_DOWN="false"

# --- Desktop notifications ---
DESKTOP_NOTIFICATIONS="false"

# ============================================================================
# COLORS
# ============================================================================
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
fi

# ============================================================================
# LOGGING
# ============================================================================
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Write to log file
    if [[ "$ENABLE_LOGGING" == "true" ]]; then
        if [[ -w "$LOG_FILE" ]] || [[ ! -e "$LOG_FILE" && -w "$(dirname "$LOG_FILE")" ]]; then
            echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
        fi
    fi

    # Terminal output
    case "$level" in
        ERROR)   echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        WARNING) echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        DEBUG)
            if [[ "$VERBOSE" == "true" ]]; then
                echo -e "${CYAN}[DEBUG]${NC} $message"
            fi
            ;;
        *)       echo -e "[INFO] $message" ;;
    esac
}

# ============================================================================
# DESKTOP NOTIFICATIONS
# ============================================================================
send_notification() {
    local summary="$1"
    local body="${2:-}"
    local urgency="${3:-normal}"

    if [[ "$DESKTOP_NOTIFICATIONS" != "true" ]]; then
        return 0
    fi

    # Try notify-send (works for most DEs)
    if command -v notify-send &>/dev/null; then
        # When running as root via dispatcher, try to send to the logged-in user
        local display_user
        display_user=$(who | awk '{print $1}' | head -1)
        if [[ -n "$display_user" ]] && [[ "$EUID" -eq 0 ]]; then
            local uid
            uid=$(id -u "$display_user" 2>/dev/null) || return 0
            sudo -u "$display_user" \
                DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
                notify-send --urgency="$urgency" \
                --app-name="Split Tunnel" \
                "$summary" "$body" 2>/dev/null || true
        else
            notify-send --urgency="$urgency" \
                --app-name="Split Tunnel" \
                "$summary" "$body" 2>/dev/null || true
        fi
    fi
}

# ============================================================================
# SAFE CONFIG PARSING (no source/eval)
# ============================================================================
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_message "WARNING" "Config file not found at $CONFIG_FILE, using defaults"
        return 0
    fi

    log_message "DEBUG" "Loading configuration from $CONFIG_FILE"

    # Validate file permissions — warn if world-writable
    local perms
    perms=$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null) || true
    if [[ -n "$perms" ]] && [[ "${perms: -1}" =~ [2367] ]]; then
        log_message "WARNING" "Config file $CONFIG_FILE is world-writable — this is a security risk"
    fi

    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((++line_num))
        # Strip leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Skip empty lines and comments
        [[ -z "$line" || "$line" == \#* ]] && continue

        # Match KEY="VALUE" or KEY=("val1" "val2" ...)
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local raw_value="${BASH_REMATCH[2]}"

            # Parse array values: ("val1" "val2" ...) or ()
            if [[ "$raw_value" =~ ^\((.*)\)$ ]]; then
                local inner="${BASH_REMATCH[1]}"
                local -a arr=()
                # Extract quoted strings (if any)
                while [[ -n "$inner" ]] && [[ "$inner" =~ \"([^\"]*)\"|\'([^\']*)\' ]]; do
                    arr+=("${BASH_REMATCH[1]}${BASH_REMATCH[2]}")
                    inner="${inner#*"${BASH_REMATCH[0]}"}"
                done
                _assign_array "$key" "${arr[@]+"${arr[@]}"}"
            else
                # Scalar value — strip surrounding quotes
                raw_value="${raw_value#\"}"
                raw_value="${raw_value%\"}"
                raw_value="${raw_value#\'}"
                raw_value="${raw_value%\'}"
                _assign_scalar "$key" "$raw_value"
            fi
        else
            log_message "DEBUG" "Ignoring unparseable config line $line_num: $line"
        fi
    done < "$CONFIG_FILE"

    # Backwards compatibility: single VPN_INTERFACE -> VPN_INTERFACES array
    if [[ -n "${VPN_INTERFACE:-}" ]]; then
        VPN_INTERFACES=("$VPN_INTERFACE")
        unset VPN_INTERFACE
    fi
}

# Safely assign scalar config values to known variables only
_assign_scalar() {
    local key="$1"
    local value="$2"

    case "$key" in
        TUNNEL_MODE)            TUNNEL_MODE="$value" ;;
        VPN_INTERFACE)          VPN_INTERFACE="$value" ;;
        ENABLE_LOGGING)         ENABLE_LOGGING="$value" ;;
        LOG_FILE)               LOG_FILE="$value" ;;
        VERBOSE)                VERBOSE="$value" ;;
        DRY_RUN)                DRY_RUN="$value" ;;
        LOCK_FILE)              LOCK_FILE="$value" ;;
        ROUTE_METRIC)           ROUTE_METRIC="$value" ;;
        VERIFY_CONNECTIVITY)    VERIFY_CONNECTIVITY="$value" ;;
        AUTO_DISCOVER_SUBNETS)  AUTO_DISCOVER_SUBNETS="$value" ;;
        KILL_SWITCH)            KILL_SWITCH="$value" ;;
        KILL_SWITCH_BACKEND)    KILL_SWITCH_BACKEND="$value" ;;
        DNS_LEAK_PREVENTION)    DNS_LEAK_PREVENTION="$value" ;;
        REMOVE_ROUTES_ON_VPN_DOWN) REMOVE_ROUTES_ON_VPN_DOWN="$value" ;;
        DESKTOP_NOTIFICATIONS)  DESKTOP_NOTIFICATIONS="$value" ;;
        *)
            log_message "DEBUG" "Ignoring unknown config key: $key"
            ;;
    esac
}

# Safely assign array config values to known variables only
_assign_array() {
    local key="$1"
    shift
    local values=("$@")

    case "$key" in
        BYPASS_SUBNETS)       BYPASS_SUBNETS=("${values[@]}") ;;
        BYPASS_SUBNETS_V6)    BYPASS_SUBNETS_V6=("${values[@]}") ;;
        VPN_INTERFACES)       VPN_INTERFACES=("${values[@]}") ;;
        VERIFY_HOSTS)         VERIFY_HOSTS=("${values[@]}") ;;
        DIRECT_DNS_SERVERS)   DIRECT_DNS_SERVERS=("${values[@]}") ;;
        *)
            log_message "DEBUG" "Ignoring unknown config array: $key"
            ;;
    esac
}

# ============================================================================
# VALIDATION
# ============================================================================

# Validate an IPv4 CIDR subnet (e.g., 192.168.1.0/24)
validate_ipv4_cidr() {
    local cidr="$1"
    if [[ ! "$cidr" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$ ]]; then
        return 1
    fi
    local o1="${BASH_REMATCH[1]}" o2="${BASH_REMATCH[2]}" o3="${BASH_REMATCH[3]}" o4="${BASH_REMATCH[4]}" prefix="${BASH_REMATCH[5]}"
    (( o1 <= 255 && o2 <= 255 && o3 <= 255 && o4 <= 255 && prefix <= 32 )) || return 1
    return 0
}

# Validate an IPv6 CIDR subnet
validate_ipv6_cidr() {
    local cidr="$1"
    # Must contain / with a prefix length
    [[ "$cidr" == */* ]] || return 1
    local addr="${cidr%/*}"
    local prefix="${cidr##*/}"
    [[ "$prefix" =~ ^[0-9]+$ ]] && (( prefix <= 128 )) || return 1
    # Validate the address portion: must only contain hex digits and colons,
    # must contain at least one colon, and not start/end with a single colon
    # (double colon :: is allowed at start/end)
    [[ "$addr" =~ ^[0-9a-fA-F:]+$ ]] || return 1
    [[ "$addr" == *:* ]] || return 1
    # Reject more than one :: group
    local double_colons="${addr//[^:]}"
    local compressed="${addr//::}"
    if [[ "$addr" == *::*::* ]]; then
        return 1
    fi
    return 0
}

# Validate entire configuration
validate_config() {
    local errors=0
    local warnings=0

    log_message "INFO" "=== Configuration Validation ==="
    log_message "INFO" "Config file: $CONFIG_FILE"
    echo ""

    # Tunnel mode
    if [[ "$TUNNEL_MODE" != "bypass" && "$TUNNEL_MODE" != "include" ]]; then
        log_message "ERROR" "TUNNEL_MODE must be 'bypass' or 'include', got: '$TUNNEL_MODE'"
        ((++errors))
    else
        log_message "SUCCESS" "TUNNEL_MODE: $TUNNEL_MODE"
    fi

    # VPN interfaces
    if [[ ${#VPN_INTERFACES[@]} -eq 0 ]]; then
        log_message "ERROR" "No VPN interfaces configured (VPN_INTERFACES is empty)"
        ((++errors))
    else
        for iface in "${VPN_INTERFACES[@]}"; do
            if ip link show "$iface" &>/dev/null; then
                log_message "SUCCESS" "VPN interface '$iface' exists"
            else
                log_message "WARNING" "VPN interface '$iface' not found (may appear when VPN connects)"
                ((++warnings))
            fi
        done
    fi

    # IPv4 subnets
    log_message "INFO" "Validating IPv4 bypass subnets (${#BYPASS_SUBNETS[@]} entries)..."
    for subnet in "${BYPASS_SUBNETS[@]}"; do
        if validate_ipv4_cidr "$subnet"; then
            log_message "SUCCESS" "  $subnet -- valid"
        else
            log_message "ERROR" "  $subnet -- INVALID IPv4 CIDR"
            ((++errors))
        fi
    done

    # IPv6 subnets
    if [[ ${#BYPASS_SUBNETS_V6[@]} -gt 0 ]]; then
        log_message "INFO" "Validating IPv6 bypass subnets (${#BYPASS_SUBNETS_V6[@]} entries)..."
        for subnet in "${BYPASS_SUBNETS_V6[@]}"; do
            if validate_ipv6_cidr "$subnet"; then
                log_message "SUCCESS" "  $subnet -- valid"
            else
                log_message "ERROR" "  $subnet -- INVALID IPv6 CIDR"
                ((++errors))
            fi
        done
    fi

    # Route metric
    if [[ -n "$ROUTE_METRIC" ]]; then
        if [[ "$ROUTE_METRIC" =~ ^[0-9]+$ ]] && (( ROUTE_METRIC >= 0 && ROUTE_METRIC <= 9999 )); then
            log_message "SUCCESS" "ROUTE_METRIC: $ROUTE_METRIC"
        else
            log_message "ERROR" "ROUTE_METRIC must be a number 0-9999, got: '$ROUTE_METRIC'"
            ((++errors))
        fi
    fi

    # Kill switch backend
    if [[ "$KILL_SWITCH" == "true" ]]; then
        if [[ "$KILL_SWITCH_BACKEND" == "iptables" ]]; then
            if ! command -v iptables &>/dev/null; then
                log_message "ERROR" "Kill switch backend 'iptables' requested but iptables not found"
                ((++errors))
            else
                log_message "SUCCESS" "Kill switch backend: iptables (available)"
            fi
        elif [[ "$KILL_SWITCH_BACKEND" == "nftables" ]]; then
            if ! command -v nft &>/dev/null; then
                log_message "ERROR" "Kill switch backend 'nftables' requested but nft not found"
                ((++errors))
            else
                log_message "SUCCESS" "Kill switch backend: nftables (available)"
            fi
        else
            log_message "ERROR" "KILL_SWITCH_BACKEND must be 'iptables' or 'nftables', got: '$KILL_SWITCH_BACKEND'"
            ((++errors))
        fi
    fi

    # DNS leak prevention
    if [[ "$DNS_LEAK_PREVENTION" == "true" && ${#DIRECT_DNS_SERVERS[@]} -eq 0 ]]; then
        log_message "WARNING" "DNS_LEAK_PREVENTION enabled but no DIRECT_DNS_SERVERS configured"
        log_message "INFO" "  The script will attempt to auto-detect gateway DNS"
        ((++warnings))
    fi

    # Verify hosts
    if [[ "$VERIFY_CONNECTIVITY" == "true" && ${#VERIFY_HOSTS[@]} -eq 0 ]]; then
        log_message "WARNING" "VERIFY_CONNECTIVITY enabled but no VERIFY_HOSTS configured"
        log_message "INFO" "  Will use gateway IP for verification"
        ((++warnings))
    fi

    echo ""
    if [[ $errors -gt 0 ]]; then
        log_message "ERROR" "Validation failed: $errors error(s), $warnings warning(s)"
        return 1
    else
        log_message "SUCCESS" "Validation passed: 0 errors, $warnings warning(s)"
        return 0
    fi
}

# ============================================================================
# ROOT / LOCK
# ============================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "This script must be run as root or with sudo"
        exit 1
    fi
}

acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null) || lock_pid=""
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            log_message "WARNING" "Another instance is running (PID: $lock_pid). Exiting."
            exit 0
        else
            log_message "DEBUG" "Removing stale lock file"
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
}

release_lock() {
    rm -f "$LOCK_FILE" 2>/dev/null || true
}

trap release_lock EXIT

# ============================================================================
# NETWORK HELPERS
# ============================================================================

# Build a grep pattern that matches any configured VPN interface
_vpn_grep_pattern() {
    local pattern=""
    for iface in "${VPN_INTERFACES[@]}"; do
        if [[ -n "$pattern" ]]; then
            pattern="${pattern}\|${iface}"
        else
            pattern="$iface"
        fi
    done
    echo "$pattern"
}

# Find default IPv4 route NOT through any VPN interface
get_default_route() {
    local vpn_pattern
    vpn_pattern=$(_vpn_grep_pattern)

    local route_info
    route_info=$(ip -4 route show default | grep -v "$vpn_pattern" | awk 'NR==1 {print $3, $5}')

    if [[ -z "$route_info" ]]; then
        return 1
    fi
    echo "$route_info"
}

# Find default IPv6 route NOT through any VPN interface
get_default_route_v6() {
    local vpn_pattern
    vpn_pattern=$(_vpn_grep_pattern)

    local route_info
    route_info=$(ip -6 route show default | grep -v "$vpn_pattern" | awk 'NR==1 {print $3, $5}')

    if [[ -z "$route_info" ]]; then
        return 1
    fi
    echo "$route_info"
}

# Discover local subnets from current network interfaces (excluding VPN + leak interfaces)
discover_local_subnets() {
    local vpn_pattern
    vpn_pattern=$(_vpn_grep_pattern)
    local -a discovered_v4=()
    local -a discovered_v6=()

    # Interfaces to always exclude (VPN artifacts, leak protection, virtual bridges)
    local exclude_pattern="${vpn_pattern}|^lo$|^virbr|^docker|^br-|^veth|ipv6leak"

    log_message "INFO" "Auto-discovering local subnets..."

    # IPv4 — use -o (one-line) format: "idx: IFACE  inet ADDR/PREFIX ..."
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local iface subnet
        iface=$(echo "$line" | awk '{print $2}')
        subnet=$(echo "$line" | awk '{print $4}')
        # Skip VPN, loopback, leak, and virtual bridge interfaces
        if echo "$iface" | grep -qE "$exclude_pattern"; then
            log_message "DEBUG" "Skipping interface $iface (excluded)"
            continue
        fi
        # Convert host address to network via ip route
        local network
        network=$(ip -4 route show "$subnet" dev "$iface" 2>/dev/null | awk '{print $1}' | head -1)
        if [[ -n "$network" && "$network" != "default" ]]; then
            discovered_v4+=("$network")
            log_message "DEBUG" "Discovered IPv4 subnet: $network on $iface"
        fi
    done < <(ip -o -4 addr show | grep -v '127.0.0.1')

    # IPv6 (link-local excluded) — use -o (one-line) format: "idx: IFACE  inet6 ADDR/PREFIX ..."
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local iface subnet
        iface=$(echo "$line" | awk '{print $2}')
        subnet=$(echo "$line" | awk '{print $4}')
        if echo "$iface" | grep -qE "$exclude_pattern"; then
            log_message "DEBUG" "Skipping IPv6 interface $iface (excluded)"
            continue
        fi
        # Skip link-local
        if [[ "$subnet" == fe80:* ]]; then
            continue
        fi
        discovered_v6+=("$subnet")
        log_message "DEBUG" "Discovered IPv6 subnet: $subnet on $iface"
    done < <(ip -o -6 addr show | grep -v 'fe80' | grep -v '::1/128')

    # Merge with configured subnets (avoid duplicates)
    for net in "${discovered_v4[@]}"; do
        local found=0
        for existing in "${BYPASS_SUBNETS[@]}"; do
            [[ "$existing" == "$net" ]] && found=1 && break
        done
        if [[ $found -eq 0 ]]; then
            BYPASS_SUBNETS+=("$net")
            log_message "SUCCESS" "Auto-added IPv4 subnet: $net"
        fi
    done

    for net in "${discovered_v6[@]}"; do
        local found=0
        for existing in "${BYPASS_SUBNETS_V6[@]+"${BYPASS_SUBNETS_V6[@]}"}"; do
            [[ "$existing" == "$net" ]] && found=1 && break
        done
        if [[ $found -eq 0 ]]; then
            BYPASS_SUBNETS_V6+=("$net")
            log_message "SUCCESS" "Auto-added IPv6 subnet: $net"
        fi
    done
}

# ============================================================================
# ROUTE MANAGEMENT -- IPv4
# ============================================================================
add_routes_v4() {
    local default_route default_interface
    if ! route_info=$(get_default_route); then
        log_message "ERROR" "No non-VPN default IPv4 route found!"
        log_message "INFO" "  Check that a physical interface has a default route"
        log_message "INFO" "  Run: ip -4 route show default"
        return 1
    fi

    read -r default_route default_interface <<< "$route_info"
    log_message "INFO" "IPv4 gateway: $default_route via $default_interface"

    local metric_arg=""
    if [[ -n "$ROUTE_METRIC" ]]; then
        metric_arg="metric $ROUTE_METRIC"
        log_message "DEBUG" "Using route metric: $ROUTE_METRIC"
    fi

    local success_count=0 fail_count=0 skip_count=0

    for subnet in "${BYPASS_SUBNETS[@]}"; do
        if ! validate_ipv4_cidr "$subnet"; then
            log_message "ERROR" "Skipping invalid IPv4 CIDR: $subnet"
            ((++fail_count))
            continue
        fi

        if ip -4 route show | grep -q "^${subnet} "; then
            log_message "DEBUG" "Route for $subnet already exists, skipping"
            ((++skip_count))
            continue
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            log_message "INFO" "[DRY RUN] Would add: $subnet via $default_route dev $default_interface $metric_arg"
            ((++success_count))
            continue
        fi

        log_message "DEBUG" "Executing: ip route add $subnet via $default_route dev $default_interface $metric_arg"

        # shellcheck disable=SC2086
        local route_err
        if route_err=$(ip route add "$subnet" via "$default_route" dev "$default_interface" $metric_arg 2>&1); then
            log_message "SUCCESS" "Added: $subnet -> $default_interface ($default_route)"
            ((++success_count))
        else
            log_message "ERROR" "Failed to add route for $subnet: ${route_err:-unknown error}"
            ((++fail_count))
        fi
    done

    log_message "INFO" "IPv4 routes -- added: $success_count, skipped: $skip_count, failed: $fail_count"
    [[ $fail_count -eq 0 ]]
}

remove_routes_v4() {
    log_message "INFO" "Removing IPv4 split tunnel routes..."
    local success_count=0 fail_count=0

    for subnet in "${BYPASS_SUBNETS[@]}"; do
        local route_line
        route_line=$(ip -4 route show "$subnet" 2>/dev/null | head -1)

        if [[ -z "$route_line" ]]; then
            log_message "DEBUG" "Route for $subnet does not exist, skipping"
            continue
        fi

        # Never remove kernel (directly-connected) routes
        if [[ "$route_line" == *"proto kernel"* ]]; then
            log_message "DEBUG" "Route for $subnet is a kernel route, skipping removal"
            continue
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            log_message "INFO" "[DRY RUN] Would remove: $subnet"
            ((++success_count))
            continue
        fi

        if ip route del "$subnet" 2>/dev/null; then
            log_message "SUCCESS" "Removed: $subnet"
            ((++success_count))
        else
            log_message "ERROR" "Failed to remove route for: $subnet"
            ((++fail_count))
        fi
    done

    log_message "INFO" "IPv4 routes removed: $success_count, failed: $fail_count"
    return 0
}

# ============================================================================
# ROUTE MANAGEMENT -- IPv6
# ============================================================================
add_routes_v6() {
    if [[ ${#BYPASS_SUBNETS_V6[@]} -eq 0 ]]; then
        log_message "DEBUG" "No IPv6 bypass subnets configured, skipping"
        return 0
    fi

    local default_route default_interface
    if ! route_info=$(get_default_route_v6); then
        log_message "WARNING" "No non-VPN default IPv6 route found, skipping IPv6 routes"
        return 0
    fi

    read -r default_route default_interface <<< "$route_info"
    log_message "INFO" "IPv6 gateway: $default_route via $default_interface"

    local metric_arg=""
    if [[ -n "$ROUTE_METRIC" ]]; then
        metric_arg="metric $ROUTE_METRIC"
    fi

    local success_count=0 fail_count=0 skip_count=0

    for subnet in "${BYPASS_SUBNETS_V6[@]}"; do
        if ip -6 route show | grep -q "^${subnet} "; then
            log_message "DEBUG" "IPv6 route for $subnet already exists, skipping"
            ((++skip_count))
            continue
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            log_message "INFO" "[DRY RUN] Would add IPv6: $subnet via $default_route dev $default_interface $metric_arg"
            ((++success_count))
            continue
        fi

        # shellcheck disable=SC2086
        local route_err
        if route_err=$(ip -6 route add "$subnet" via "$default_route" dev "$default_interface" $metric_arg 2>&1); then
            log_message "SUCCESS" "Added IPv6: $subnet -> $default_interface ($default_route)"
            ((++success_count))
        else
            log_message "ERROR" "Failed to add IPv6 route for $subnet: ${route_err:-unknown error}"
            ((++fail_count))
        fi
    done

    log_message "INFO" "IPv6 routes -- added: $success_count, skipped: $skip_count, failed: $fail_count"
    [[ $fail_count -eq 0 ]]
}

remove_routes_v6() {
    if [[ ${#BYPASS_SUBNETS_V6[@]} -eq 0 ]]; then
        return 0
    fi

    log_message "INFO" "Removing IPv6 split tunnel routes..."
    local success_count=0 fail_count=0

    for subnet in "${BYPASS_SUBNETS_V6[@]}"; do
        local route_line
        route_line=$(ip -6 route show "$subnet" 2>/dev/null | head -1)

        if [[ -z "$route_line" ]]; then
            log_message "DEBUG" "IPv6 route for $subnet does not exist, skipping"
            continue
        fi

        # Never remove kernel (directly-connected) routes
        if [[ "$route_line" == *"proto kernel"* ]]; then
            log_message "DEBUG" "IPv6 route for $subnet is a kernel route, skipping removal"
            continue
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            log_message "INFO" "[DRY RUN] Would remove IPv6: $subnet"
            ((++success_count))
            continue
        fi

        if ip -6 route del "$subnet" 2>/dev/null; then
            log_message "SUCCESS" "Removed IPv6: $subnet"
            ((++success_count))
        else
            log_message "ERROR" "Failed to remove IPv6 route for: $subnet"
            ((++fail_count))
        fi
    done

    log_message "INFO" "IPv6 routes removed: $success_count, failed: $fail_count"
    return 0
}

# ============================================================================
# INCLUDE MODE -- route only specific subnets through VPN
# ============================================================================
add_routes_include_mode() {
    log_message "INFO" "Include mode: routing only configured subnets through VPN"

    local vpn_iface="${VPN_INTERFACES[0]}"

    # Get VPN gateway
    local vpn_gw
    vpn_gw=$(ip -4 route show default dev "$vpn_iface" 2>/dev/null | awk '{print $3}' | head -1)
    if [[ -z "$vpn_gw" ]]; then
        log_message "ERROR" "Cannot determine VPN gateway for $vpn_iface"
        return 1
    fi

    local metric_arg=""
    if [[ -n "$ROUTE_METRIC" ]]; then
        metric_arg="metric $ROUTE_METRIC"
    fi

    local success_count=0 fail_count=0

    for subnet in "${BYPASS_SUBNETS[@]}"; do
        if ! validate_ipv4_cidr "$subnet"; then
            log_message "ERROR" "Skipping invalid CIDR: $subnet"
            ((++fail_count))
            continue
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            log_message "INFO" "[DRY RUN] Would route $subnet through VPN ($vpn_iface via $vpn_gw)"
            ((++success_count))
            continue
        fi

        # shellcheck disable=SC2086
        if ip route replace "$subnet" via "$vpn_gw" dev "$vpn_iface" $metric_arg 2>/dev/null; then
            log_message "SUCCESS" "VPN-routed: $subnet -> $vpn_iface ($vpn_gw)"
            ((++success_count))
        else
            log_message "ERROR" "Failed to VPN-route: $subnet"
            ((++fail_count))
        fi
    done

    log_message "INFO" "Include mode routes -- added: $success_count, failed: $fail_count"
    [[ $fail_count -eq 0 ]]
}

# ============================================================================
# DNS LEAK PREVENTION
# ============================================================================
setup_dns_leak_prevention() {
    if [[ "$DNS_LEAK_PREVENTION" != "true" ]]; then
        return 0
    fi

    log_message "INFO" "Setting up DNS leak prevention..."

    local default_route default_interface
    if ! route_info=$(get_default_route); then
        log_message "WARNING" "Cannot set up DNS leak prevention -- no default route found"
        return 0
    fi
    read -r default_route default_interface <<< "$route_info"

    # If no explicit DNS servers, use the gateway
    local dns_servers=("${DIRECT_DNS_SERVERS[@]+"${DIRECT_DNS_SERVERS[@]}"}")
    if [[ ${#dns_servers[@]} -eq 0 ]]; then
        dns_servers=("$default_route")
        log_message "DEBUG" "Using gateway $default_route as direct DNS server"
    fi

    local metric_arg=""
    if [[ -n "$ROUTE_METRIC" ]]; then
        metric_arg="metric $ROUTE_METRIC"
    fi

    for dns in "${dns_servers[@]}"; do
        local dns_route="${dns}/32"
        if ip -4 route show | grep -q "^${dns_route} "; then
            log_message "DEBUG" "DNS route for $dns already exists"
            continue
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            log_message "INFO" "[DRY RUN] Would add DNS route: $dns via $default_route dev $default_interface"
            continue
        fi

        # shellcheck disable=SC2086
        if ip route add "${dns_route}" via "$default_route" dev "$default_interface" $metric_arg 2>/dev/null; then
            log_message "SUCCESS" "DNS route added: $dns -> $default_interface"
        else
            log_message "WARNING" "Failed to add DNS route for $dns (may already exist)"
        fi
    done
}

remove_dns_leak_prevention() {
    if [[ "$DNS_LEAK_PREVENTION" != "true" ]]; then
        return 0
    fi

    local dns_servers=("${DIRECT_DNS_SERVERS[@]+"${DIRECT_DNS_SERVERS[@]}"}")
    if route_info=$(get_default_route); then
        local default_route
        read -r default_route _ <<< "$route_info"
        if [[ ${#dns_servers[@]} -eq 0 ]]; then
            dns_servers=("$default_route")
        fi
    fi

    for dns in "${dns_servers[@]}"; do
        ip route del "${dns}/32" 2>/dev/null || true
    done
}

# ============================================================================
# KILL SWITCH
# ============================================================================
enable_kill_switch() {
    if [[ "$KILL_SWITCH" != "true" ]]; then
        return 0
    fi

    log_message "INFO" "Enabling kill switch ($KILL_SWITCH_BACKEND)..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_message "INFO" "[DRY RUN] Would enable kill switch"
        return 0
    fi

    if [[ "$KILL_SWITCH_BACKEND" == "iptables" ]]; then
        _enable_kill_switch_iptables
    elif [[ "$KILL_SWITCH_BACKEND" == "nftables" ]]; then
        _enable_kill_switch_nftables
    fi
}

disable_kill_switch() {
    if [[ "$KILL_SWITCH" != "true" ]]; then
        return 0
    fi

    log_message "INFO" "Disabling kill switch..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_message "INFO" "[DRY RUN] Would disable kill switch"
        return 0
    fi

    if [[ "$KILL_SWITCH_BACKEND" == "iptables" ]]; then
        _disable_kill_switch_iptables
    elif [[ "$KILL_SWITCH_BACKEND" == "nftables" ]]; then
        _disable_kill_switch_nftables
    fi
}

_enable_kill_switch_iptables() {
    # Create chain if it doesn't exist
    iptables -N "$IPTABLES_CHAIN" 2>/dev/null || true
    iptables -F "$IPTABLES_CHAIN"

    # Allow loopback
    iptables -A "$IPTABLES_CHAIN" -o lo -j ACCEPT

    # Allow VPN interfaces
    for iface in "${VPN_INTERFACES[@]}"; do
        iptables -A "$IPTABLES_CHAIN" -o "$iface" -j ACCEPT
    done

    # Allow bypass subnets
    for subnet in "${BYPASS_SUBNETS[@]}"; do
        iptables -A "$IPTABLES_CHAIN" -d "$subnet" -j ACCEPT
    done

    # Allow established connections
    iptables -A "$IPTABLES_CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # Allow DHCP
    iptables -A "$IPTABLES_CHAIN" -p udp --dport 67:68 -j ACCEPT

    # Allow DNS to direct servers
    if [[ "$DNS_LEAK_PREVENTION" == "true" ]]; then
        for dns in "${DIRECT_DNS_SERVERS[@]+"${DIRECT_DNS_SERVERS[@]}"}"; do
            iptables -A "$IPTABLES_CHAIN" -d "$dns" -p udp --dport 53 -j ACCEPT
            iptables -A "$IPTABLES_CHAIN" -d "$dns" -p tcp --dport 53 -j ACCEPT
        done
    fi

    # Drop everything else
    iptables -A "$IPTABLES_CHAIN" -j DROP

    # Insert into OUTPUT if not already present
    if ! iptables -C OUTPUT -j "$IPTABLES_CHAIN" 2>/dev/null; then
        iptables -I OUTPUT -j "$IPTABLES_CHAIN"
    fi

    # IPv6
    if command -v ip6tables &>/dev/null; then
        ip6tables -N "$IP6TABLES_CHAIN" 2>/dev/null || true
        ip6tables -F "$IP6TABLES_CHAIN"
        ip6tables -A "$IP6TABLES_CHAIN" -o lo -j ACCEPT
        for iface in "${VPN_INTERFACES[@]}"; do
            ip6tables -A "$IP6TABLES_CHAIN" -o "$iface" -j ACCEPT
        done
        for subnet in "${BYPASS_SUBNETS_V6[@]+"${BYPASS_SUBNETS_V6[@]}"}"; do
            ip6tables -A "$IP6TABLES_CHAIN" -d "$subnet" -j ACCEPT
        done
        ip6tables -A "$IP6TABLES_CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        ip6tables -A "$IP6TABLES_CHAIN" -j DROP
        if ! ip6tables -C OUTPUT -j "$IP6TABLES_CHAIN" 2>/dev/null; then
            ip6tables -I OUTPUT -j "$IP6TABLES_CHAIN"
        fi
    fi

    log_message "SUCCESS" "Kill switch enabled (iptables)"
}

_disable_kill_switch_iptables() {
    iptables -D OUTPUT -j "$IPTABLES_CHAIN" 2>/dev/null || true
    iptables -F "$IPTABLES_CHAIN" 2>/dev/null || true
    iptables -X "$IPTABLES_CHAIN" 2>/dev/null || true

    if command -v ip6tables &>/dev/null; then
        ip6tables -D OUTPUT -j "$IP6TABLES_CHAIN" 2>/dev/null || true
        ip6tables -F "$IP6TABLES_CHAIN" 2>/dev/null || true
        ip6tables -X "$IP6TABLES_CHAIN" 2>/dev/null || true
    fi

    log_message "SUCCESS" "Kill switch disabled (iptables)"
}

_enable_kill_switch_nftables() {
    nft add table inet "$NFTABLES_TABLE" 2>/dev/null || true
    nft flush table inet "$NFTABLES_TABLE" 2>/dev/null || true

    local rules="table inet $NFTABLES_TABLE {
    chain output {
        type filter hook output priority 0; policy accept;
        oifname \"lo\" accept
"
    for iface in "${VPN_INTERFACES[@]}"; do
        rules+="        oifname \"$iface\" accept
"
    done
    for subnet in "${BYPASS_SUBNETS[@]}"; do
        rules+="        ip daddr $subnet accept
"
    done
    for subnet in "${BYPASS_SUBNETS_V6[@]+"${BYPASS_SUBNETS_V6[@]}"}"; do
        rules+="        ip6 daddr $subnet accept
"
    done
    rules+="        ct state established,related accept
        udp dport { 67, 68 } accept
        drop
    }
}"

    echo "$rules" | nft -f - 2>/dev/null
    log_message "SUCCESS" "Kill switch enabled (nftables)"
}

_disable_kill_switch_nftables() {
    nft delete table inet "$NFTABLES_TABLE" 2>/dev/null || true
    log_message "SUCCESS" "Kill switch disabled (nftables)"
}

# ============================================================================
# CONNECTIVITY VERIFICATION
# ============================================================================
verify_connectivity() {
    if [[ "$VERIFY_CONNECTIVITY" != "true" ]]; then
        return 0
    fi

    log_message "INFO" "Verifying connectivity to bypass subnets..."

    local hosts=("${VERIFY_HOSTS[@]+"${VERIFY_HOSTS[@]}"}")

    if [[ ${#hosts[@]} -eq 0 ]]; then
        if route_info=$(get_default_route); then
            local gw
            read -r gw _ <<< "$route_info"
            hosts=("$gw")
        fi
    fi

    if [[ ${#hosts[@]} -eq 0 ]]; then
        log_message "WARNING" "No hosts to verify connectivity against"
        return 0
    fi

    local pass=0 fail=0
    for host in "${hosts[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_message "INFO" "[DRY RUN] Would ping $host"
            ((++pass))
            continue
        fi

        if ping -c 1 -W 3 "$host" &>/dev/null; then
            log_message "SUCCESS" "Reachable: $host"
            ((++pass))
        else
            log_message "WARNING" "Unreachable: $host"
            ((++fail))
        fi
    done

    log_message "INFO" "Connectivity check: $pass reachable, $fail unreachable"

    if [[ $fail -gt 0 ]]; then
        send_notification "Split Tunnel Warning" "$fail host(s) unreachable after route change" "critical"
    fi
}

# ============================================================================
# COMBINED ADD / REMOVE
# ============================================================================
add_routes() {
    local start_time
    start_time=$(date +%s%N 2>/dev/null || date +%s)

    if [[ "$AUTO_DISCOVER_SUBNETS" == "true" ]]; then
        discover_local_subnets
    fi

    local exit_code=0

    if [[ "$TUNNEL_MODE" == "include" ]]; then
        add_routes_include_mode || exit_code=1
    else
        add_routes_v4 || exit_code=1
        add_routes_v6 || exit_code=$?
    fi

    setup_dns_leak_prevention
    enable_kill_switch
    verify_connectivity

    if [[ $exit_code -eq 0 ]]; then
        local end_time duration_ms
        end_time=$(date +%s%N 2>/dev/null || date +%s)
        if [[ ${#start_time} -gt 10 && ${#end_time} -gt 10 ]]; then
            duration_ms=$(( (end_time - start_time) / 1000000 ))
        else
            duration_ms=$(( (end_time - start_time) * 1000 ))
        fi
        log_message "SUCCESS" "Split tunneling is now active (mode: $TUNNEL_MODE) [${duration_ms}ms]"
        send_notification "Split Tunnel Active" "Routes configured in $TUNNEL_MODE mode"
    else
        log_message "WARNING" "Split tunneling partially active -- check errors above"
        send_notification "Split Tunnel Warning" "Some routes failed to apply" "critical"
    fi

    return $exit_code
}

remove_routes() {
    remove_routes_v4
    remove_routes_v6
    remove_dns_leak_prevention
    disable_kill_switch

    log_message "SUCCESS" "All split tunnel routes removed"
    send_notification "Split Tunnel Removed" "All bypass routes have been removed"
}

# Reload: remove old routes and re-apply with current config
reload_routes() {
    log_message "INFO" "Reloading split tunnel configuration..."
    remove_routes
    load_config
    add_routes
}

# ============================================================================
# STATUS
# ============================================================================
show_status() {
    echo -e "${BOLD}=== Split Tunnel Status (v${VERSION}) ===${NC}"
    echo ""

    # Mode
    echo -e "${BOLD}Mode:${NC} $TUNNEL_MODE"
    echo ""

    # VPN interfaces
    echo -e "${BOLD}VPN Interfaces:${NC}"
    for iface in "${VPN_INTERFACES[@]}"; do
        local state
        if ip link show "$iface" &>/dev/null; then
            state=$(ip link show "$iface" | grep -oP 'state \K\w+' || echo "UNKNOWN")
            if [[ "$state" == "UP" ]]; then
                echo -e "  ${GREEN}*${NC} $iface -- $state"
            else
                echo -e "  ${YELLOW}*${NC} $iface -- $state"
            fi
        else
            echo -e "  ${RED}*${NC} $iface -- NOT FOUND"
        fi
    done
    echo ""

    # Default route
    echo -e "${BOLD}Default Routes:${NC}"
    if route_info=$(get_default_route); then
        local gw iface
        read -r gw iface <<< "$route_info"
        echo -e "  IPv4: $gw via $iface"
    else
        echo -e "  IPv4: ${YELLOW}No non-VPN default route${NC}"
    fi
    if route_info=$(get_default_route_v6); then
        local gw iface
        read -r gw iface <<< "$route_info"
        echo -e "  IPv6: $gw via $iface"
    else
        echo -e "  IPv6: ${YELLOW}No non-VPN default route${NC}"
    fi
    echo ""

    # IPv4 subnets
    echo -e "${BOLD}IPv4 Bypass Subnets:${NC}"
    for subnet in "${BYPASS_SUBNETS[@]}"; do
        if ip -4 route show | grep -q "^${subnet} "; then
            local details
            details=$(ip -4 route show "$subnet" 2>/dev/null | head -1)
            echo -e "  ${GREEN}OK${NC} $subnet -- ${details}"
        else
            echo -e "  ${RED}--${NC} $subnet -- not active"
        fi
    done
    echo ""

    # IPv6 subnets
    if [[ ${#BYPASS_SUBNETS_V6[@]} -gt 0 ]]; then
        echo -e "${BOLD}IPv6 Bypass Subnets:${NC}"
        for subnet in "${BYPASS_SUBNETS_V6[@]}"; do
            if ip -6 route show | grep -q "^${subnet} "; then
                local details
                details=$(ip -6 route show "$subnet" 2>/dev/null | head -1)
                echo -e "  ${GREEN}OK${NC} $subnet -- ${details}"
            else
                echo -e "  ${RED}--${NC} $subnet -- not active"
            fi
        done
        echo ""
    fi

    # Kill switch
    local ks_status="disabled"
    if [[ "$KILL_SWITCH" == "true" ]]; then
        if [[ "$KILL_SWITCH_BACKEND" == "iptables" ]]; then
            if iptables -L "$IPTABLES_CHAIN" &>/dev/null 2>&1; then
                ks_status="${GREEN}ACTIVE (iptables)${NC}"
            else
                ks_status="${YELLOW}CONFIGURED but inactive${NC}"
            fi
        else
            if nft list table inet "$NFTABLES_TABLE" &>/dev/null 2>&1; then
                ks_status="${GREEN}ACTIVE (nftables)${NC}"
            else
                ks_status="${YELLOW}CONFIGURED but inactive${NC}"
            fi
        fi
    fi
    echo -e "${BOLD}Kill Switch:${NC} $ks_status"

    # DNS leak prevention
    local dns_status="disabled"
    [[ "$DNS_LEAK_PREVENTION" == "true" ]] && dns_status="${GREEN}enabled${NC}"
    echo -e "${BOLD}DNS Leak Prevention:${NC} $dns_status"

    # Features
    echo -e "${BOLD}Auto-discover:${NC} $AUTO_DISCOVER_SUBNETS"
    echo -e "${BOLD}Connectivity verify:${NC} $VERIFY_CONNECTIVITY"
    echo -e "${BOLD}Desktop notifications:${NC} $DESKTOP_NOTIFICATIONS"
    echo -e "${BOLD}VPN-down cleanup:${NC} $REMOVE_ROUTES_ON_VPN_DOWN"
    echo ""
}

# ============================================================================
# USAGE
# ============================================================================
usage() {
    cat << EOF
NetworkManager Split Tunnel Script v${VERSION}

USAGE:
    $SCRIPT_NAME <command> [options]

COMMANDS:
    add             Add split tunnel routes (default)
    remove          Remove all split tunnel routes
    reload          Remove old routes and re-apply from current config
    status          Show current split tunnel status
    test            Dry-run -- show what would happen without changes
    validate        Validate configuration file without modifying routes
    discover        Auto-discover and display local subnets
    kill-switch-on  Manually enable the kill switch
    kill-switch-off Manually disable the kill switch
    version         Show version information
    help            Show this help message

OPTIONS:
    -v, --verbose   Enable verbose/debug output
    -c, --config    Specify alternate config file path
    -n, --dry-run   Dry-run mode (same as 'test' command)

EXAMPLES:
    $SCRIPT_NAME add                 # Add split tunnel routes
    $SCRIPT_NAME add -v              # Add routes with verbose output
    $SCRIPT_NAME remove              # Remove all routes
    $SCRIPT_NAME reload              # Re-read config and re-apply
    $SCRIPT_NAME status              # Check current status
    $SCRIPT_NAME test                # Dry-run test
    $SCRIPT_NAME validate            # Validate config
    $SCRIPT_NAME discover            # Show discovered subnets
    $SCRIPT_NAME -c /path/to/conf add  # Use alternate config

CONFIGURATION:
    Config file : $CONFIG_FILE
    Log file    : $LOG_FILE
    Lock file   : $LOCK_FILE

MODES:
    bypass  -- Listed subnets bypass VPN (default, most common)
    include -- ONLY listed subnets go through VPN, everything else is direct

EOF
    exit 0
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    # Parse global options first
    local args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            -c|--config)
                if [[ -n "${2:-}" ]]; then
                    CONFIG_FILE="$2"
                    shift 2
                else
                    log_message "ERROR" "--config requires a path argument"
                    exit 1
                fi
                ;;
            -n|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    local action="${args[0]:-add}"

    case "$action" in
        add)
            check_root
            acquire_lock
            load_config
            add_routes
            ;;
        remove)
            check_root
            acquire_lock
            load_config
            remove_routes
            ;;
        reload)
            check_root
            acquire_lock
            load_config
            reload_routes
            ;;
        status)
            load_config
            show_status
            ;;
        test)
            check_root
            load_config
            DRY_RUN="true"
            log_message "INFO" "Running in DRY RUN mode -- no changes will be made"
            add_routes
            ;;
        validate)
            load_config
            validate_config
            ;;
        discover)
            load_config
            discover_local_subnets
            echo ""
            log_message "INFO" "Discovered IPv4 subnets:"
            for s in "${BYPASS_SUBNETS[@]}"; do echo "  $s"; done
            if [[ ${#BYPASS_SUBNETS_V6[@]} -gt 0 ]]; then
                log_message "INFO" "Discovered IPv6 subnets:"
                for s in "${BYPASS_SUBNETS_V6[@]}"; do echo "  $s"; done
            fi
            ;;
        kill-switch-on)
            check_root
            load_config
            KILL_SWITCH="true"
            enable_kill_switch
            ;;
        kill-switch-off)
            check_root
            load_config
            KILL_SWITCH="true"
            disable_kill_switch
            ;;
        version|--version)
            echo "split_tunnel v${VERSION}"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            log_message "ERROR" "Unknown command: $action"
            echo "Run '$SCRIPT_NAME help' for usage information"
            exit 1
            ;;
    esac
}

# ============================================================================
# DISPATCHER ENTRY POINT
# ============================================================================
KNOWN_COMMANDS="add|remove|reload|status|test|validate|discover|kill-switch-on|kill-switch-off|version|help"

if [[ $# -ge 2 ]] && [[ ! "$1" =~ ^($KNOWN_COMMANDS)$ ]] && [[ ! "$1" =~ ^- ]]; then
    # Called by NetworkManager dispatcher
    NM_INTERFACE="$1"
    NM_ACTION="$2"

    check_root
    load_config

    case "$NM_ACTION" in
        up|vpn-up)
            log_message "INFO" "NetworkManager event: $NM_ACTION on $NM_INTERFACE"

            # Cooldown: skip if same event was processed recently (within 5s)
            cooldown_file="/tmp/.split_tunnel_cooldown_${NM_ACTION}"
            if [[ -f "$cooldown_file" ]]; then
                last_run=$(cat "$cooldown_file" 2>/dev/null) || last_run=0
                now=$(date +%s)
                if (( now - last_run < 5 )); then
                    log_message "DEBUG" "Cooldown active, skipping duplicate $NM_ACTION event"
                    exit 0
                fi
            fi
            date +%s > "$cooldown_file" 2>/dev/null || true

            acquire_lock
            add_routes
            ;;
        down|vpn-down)
            log_message "INFO" "NetworkManager event: $NM_ACTION on $NM_INTERFACE"
            if [[ "$REMOVE_ROUTES_ON_VPN_DOWN" == "true" ]]; then
                acquire_lock
                remove_routes
                log_message "INFO" "Routes cleaned up on $NM_ACTION"
            else
                log_message "DEBUG" "REMOVE_ROUTES_ON_VPN_DOWN is false, keeping routes"
            fi
            ;;
        *)
            log_message "DEBUG" "Ignoring NetworkManager event: $NM_ACTION on $NM_INTERFACE"
            ;;
    esac
else
    # Called manually
    main "$@"
fi
