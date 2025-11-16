#!/bin/bash
# NetworkManager Split Tunnel Script
# For automatic switching, place in /etc/NetworkManager/dispatcher.d/99-split-tunnel
# Version: 2.0

set -euo pipefail

# Configuration
SCRIPT_NAME="$(basename "$0")"
CONFIG_FILE="/etc/split_tunnel/split_tunnel.conf"
LOG_FILE="/var/log/split_tunnel.log"
LOCK_FILE="/var/run/split_tunnel.lock"

# Default settings (can be overridden by config file)
BYPASS_SUBNETS=("192.168.1.0/24" "192.168.2.0/24")
VPN_INTERFACE="tun0"
ENABLE_LOGGING="true"
DRY_RUN="false"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ "$ENABLE_LOGGING" == "true" ]] && [[ -w "$LOG_FILE" || ! -e "$LOG_FILE" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    fi
    
    case "$level" in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        WARNING)
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        *)
            echo "[INFO] $message"
            ;;
    esac
}

# Load configuration file if it exists
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_message "INFO" "Loading configuration from $CONFIG_FILE"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    else
        log_message "WARNING" "Config file not found at $CONFIG_FILE, using defaults"
    fi
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "This script must be run as root or with sudo"
        exit 1
    fi
}

# Acquire lock to prevent concurrent execution
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid=$(cat "$LOCK_FILE")
        if kill -0 "$lock_pid" 2>/dev/null; then
            log_message "WARNING" "Another instance is running (PID: $lock_pid). Exiting."
            exit 0
        else
            log_message "INFO" "Removing stale lock file"
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
}

# Release lock
release_lock() {
    rm -f "$LOCK_FILE"
}

# Trap to ensure lock is released
trap release_lock EXIT

# Find the default route that is NOT through the VPN
get_default_route() {
    local route_info
    route_info=$(ip route show default | grep -v "$VPN_INTERFACE" | awk 'NR==1 {print $3, $5}')
    
    if [[ -z "$route_info" ]]; then
        return 1
    fi
    
    echo "$route_info"
    return 0
}

# Add routes for bypass subnets
add_routes() {
    local default_route default_interface
    
    if ! route_info=$(get_default_route); then
        log_message "ERROR" "No non-VPN default route or interface found!"
        return 1
    fi
    
    read -r default_route default_interface <<< "$route_info"
    
    log_message "INFO" "Using interface: $default_interface with gateway: $default_route"
    
    local success_count=0
    local fail_count=0
    
    for subnet in "${BYPASS_SUBNETS[@]}"; do
        # Check if route already exists
        if ip route show | grep -q "^$subnet"; then
            log_message "INFO" "Route for $subnet already exists, skipping"
            continue
        fi
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_message "INFO" "[DRY RUN] Would add route: $subnet via $default_route dev $default_interface"
            ((success_count++))
            continue
        fi
        
        log_message "INFO" "Adding route for $subnet via $default_interface ($default_route)..."
        
        if ip route add "$subnet" via "$default_route" dev "$default_interface" 2>/dev/null; then
            log_message "SUCCESS" "Added: $subnet -> $default_interface ($default_route)"
            ((success_count++))
        else
            log_message "ERROR" "Failed to add route for: $subnet"
            ((fail_count++))
        fi
    done
    
    log_message "INFO" "Routes added: $success_count, Failed: $fail_count"
    
    if [[ $fail_count -eq 0 ]]; then
        log_message "SUCCESS" "Split tunneling for local subnets is now active"
        return 0
    else
        return 1
    fi
}

# Remove routes for bypass subnets
remove_routes() {
    log_message "INFO" "Removing split tunnel routes..."
    
    local success_count=0
    local fail_count=0
    
    for subnet in "${BYPASS_SUBNETS[@]}"; do
        if ! ip route show | grep -q "^$subnet"; then
            log_message "INFO" "Route for $subnet does not exist, skipping"
            continue
        fi
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_message "INFO" "[DRY RUN] Would remove route: $subnet"
            ((success_count++))
            continue
        fi
        
        if ip route del "$subnet" 2>/dev/null; then
            log_message "SUCCESS" "Removed route for: $subnet"
            ((success_count++))
        else
            log_message "ERROR" "Failed to remove route for: $subnet"
            ((fail_count++))
        fi
    done
    
    log_message "INFO" "Routes removed: $success_count, Failed: $fail_count"
    return 0
}

# Show current status
show_status() {
    log_message "INFO" "=== Split Tunnel Status ==="
    
    if route_info=$(get_default_route); then
        read -r default_route default_interface <<< "$route_info"
        log_message "INFO" "Default interface: $default_interface"
        log_message "INFO" "Default gateway: $default_route"
    else
        log_message "WARNING" "No non-VPN default route found"
    fi
    
    echo ""
    log_message "INFO" "Configured bypass subnets:"
    for subnet in "${BYPASS_SUBNETS[@]}"; do
        if ip route show | grep -q "^$subnet"; then
            local route_details=$(ip route show "$subnet")
            log_message "SUCCESS" "✓ $subnet - Active ($route_details)"
        else
            log_message "WARNING" "✗ $subnet - Not active"
        fi
    done
    
    echo ""
    log_message "INFO" "VPN Interface ($VPN_INTERFACE): $(ip link show "$VPN_INTERFACE" 2>/dev/null | grep -q "state UP" && echo "UP" || echo "DOWN/NOT FOUND")"
}

# Show usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTION]

NetworkManager Split Tunnel Script - Route specific subnets outside VPN

OPTIONS:
    add         Add split tunnel routes (default action)
    remove      Remove split tunnel routes
    status      Show current split tunnel status
    test        Test configuration without making changes (dry run)
    help        Show this help message

EXAMPLES:
    $SCRIPT_NAME add          # Add split tunnel routes
    $SCRIPT_NAME remove       # Remove split tunnel routes
    $SCRIPT_NAME status       # Check current status
    $SCRIPT_NAME test         # Test without making changes

CONFIGURATION:
    Config file: $CONFIG_FILE
    Log file: $LOG_FILE

EOF
    exit 0
}

# Main function
main() {
    local action="${1:-add}"
    
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
        status)
            load_config
            show_status
            ;;
        test)
            check_root
            load_config
            DRY_RUN="true"
            log_message "INFO" "Running in DRY RUN mode - no changes will be made"
            add_routes
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            log_message "ERROR" "Unknown action: $action"
            usage
            ;;
    esac
}

# When called by NetworkManager dispatcher, arguments are passed
# $1 is interface name, $2 is action (up, down, vpn-up, vpn-down)
if [[ $# -ge 2 ]] && [[ "$1" != "add" ]] && [[ "$1" != "remove" ]] && [[ "$1" != "status" ]] && [[ "$1" != "test" ]]; then
    # Called by NetworkManager dispatcher
    INTERFACE="$1"
    ACTION="$2"
    
    check_root
    load_config
    
    case "$ACTION" in
        up|vpn-up)
            log_message "INFO" "NetworkManager event: $ACTION on $INTERFACE"
            acquire_lock
            add_routes
            ;;
        down|vpn-down)
            log_message "INFO" "NetworkManager event: $ACTION on $INTERFACE"
            # Optionally remove routes on VPN disconnect
            ;;
    esac
else
    # Called manually
    main "$@"
fi
