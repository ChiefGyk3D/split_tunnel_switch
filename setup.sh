#!/bin/bash
# NetworkManager Split Tunnel Setup Script v3.0.0
# Interactive installation, configuration, and management tool
#
# Copyright (C) 2025-2026 ChiefGyk3D
# License: GPL-3.0-or-later

set -euo pipefail

# ============================================================================
# Configuration paths
# ============================================================================
SCRIPT_NAME="split_tunnel.sh"
INSTALL_PATH="/etc/NetworkManager/dispatcher.d/99-split-tunnel"
CONFIG_DIR="/etc/split_tunnel"
CONFIG_FILE="$CONFIG_DIR/split_tunnel.conf"
CONFIG_EXAMPLE="split_tunnel.conf.example"
LOG_FILE="/var/log/split_tunnel.log"
LOGROTATE_SRC="extras/logrotate.d/split_tunnel"
LOGROTATE_DST="/etc/logrotate.d/split_tunnel"
SYSTEMD_SERVICE_SRC="extras/systemd/split-tunnel-persist.service"
SYSTEMD_TIMER_SRC="extras/systemd/split-tunnel-persist.timer"
SYSTEMD_SERVICE_DST="/etc/systemd/system/split-tunnel-persist.service"
SYSTEMD_TIMER_DST="/etc/systemd/system/split-tunnel-persist.timer"
TEST_SCRIPT="tests/run_tests.sh"
TWINGATE_SHIM_SRC="src/twingate_no_binddev.c"
TWINGATE_SHIM_DST="/usr/local/lib/twingate-no-binddev.so"
TWINGATE_DROP_IN_DIR="/etc/systemd/system/twingate.service.d"
TWINGATE_DROP_IN="${TWINGATE_DROP_IN_DIR}/no-bindtodevice.conf"
ALIASES_FILE="/etc/profile.d/split-tunnel-aliases.sh"

# ============================================================================
# Colors
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

print_header() {
    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}  NetworkManager Split Tunnel Setup  v3.0.0${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
}

# ============================================================================
# Helpers
# ============================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
}

check_prerequisites() {
    print_info "Checking prerequisites..."
    local missing=()

    for cmd in ip awk grep systemctl ping; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing[*]}"
        exit 1
    fi

    if ! systemctl is-active --quiet NetworkManager 2>/dev/null; then
        print_warning "NetworkManager is not running"
        read -rp "Continue anyway? (y/n): " -n 1
        echo
        [[ $REPLY =~ ^[Yy]$ ]] || exit 1
    fi

    # Optional dependencies
    command -v iptables &>/dev/null || print_warning "iptables not found (kill switch with iptables backend unavailable)"
    command -v nft &>/dev/null      || print_info "nft not found (kill switch with nftables backend unavailable)"
    command -v notify-send &>/dev/null || print_info "notify-send not found (desktop notifications unavailable)"
    command -v shellcheck &>/dev/null  || print_info "shellcheck not found (test suite linting unavailable)"
    command -v gcc &>/dev/null          || print_info "gcc not found (Twingate relay bypass shim build unavailable — install build-essential)"

    print_success "Prerequisites check complete"
}

backup_existing() {
    local ts
    ts=$(date +%Y%m%d_%H%M%S)

    for f in "$INSTALL_PATH" "$CONFIG_FILE"; do
        if [[ -f "$f" ]]; then
            local bak="${f}.backup.${ts}"
            print_info "Backing up $f -> $bak"
            cp "$f" "$bak"
        fi
    done
}

# ============================================================================
# Subnet validation (strict)
# ============================================================================
validate_ipv4_cidr() {
    local cidr="$1"
    if [[ ! "$cidr" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$ ]]; then
        return 1
    fi
    local o1="${BASH_REMATCH[1]}" o2="${BASH_REMATCH[2]}" o3="${BASH_REMATCH[3]}" o4="${BASH_REMATCH[4]}" p="${BASH_REMATCH[5]}"
    (( o1 <= 255 && o2 <= 255 && o3 <= 255 && o4 <= 255 && p <= 32 )) || return 1
}

validate_ipv6_cidr() {
    local cidr="$1"
    [[ "$cidr" == */* ]] || return 1
    local prefix="${cidr##*/}"
    [[ "$prefix" =~ ^[0-9]+$ ]] && (( prefix <= 128 )) || return 1
}

# ============================================================================
# Interactive configuration
# ============================================================================
configure_tunnel_mode() {
    echo ""
    print_info "Select tunnel mode:"
    echo "  1) bypass  — Listed subnets skip VPN (most common)"
    echo "  2) include — ONLY listed subnets go through VPN"
    echo ""
    read -rp "Choice [1]: " -n 1 choice
    echo
    case "$choice" in
        2) echo "include" ;;
        *) echo "bypass" ;;
    esac
}

configure_subnets_v4() {
    print_info "Configure IPv4 bypass subnets"
    echo "Enter subnets in CIDR notation, one per line."
    echo "Press Enter on an empty line when done."
    echo "  Examples: 192.168.1.0/24  10.0.0.0/8  172.16.0.0/12"
    echo ""

    local subnets=()
    while true; do
        read -rp "IPv4 subnet (or Enter to finish): " subnet
        [[ -z "$subnet" ]] && break

        if validate_ipv4_cidr "$subnet"; then
            subnets+=("$subnet")
            print_success "Added: $subnet"
        else
            print_error "Invalid IPv4 CIDR: $subnet — octets must be 0-255, prefix 0-32"
        fi
    done

    if [[ ${#subnets[@]} -eq 0 ]]; then
        print_warning "No subnets entered, using defaults: 192.168.1.0/24 192.168.2.0/24"
        subnets=("192.168.1.0/24" "192.168.2.0/24")
    fi

    printf '"%s" ' "${subnets[@]}"
}

configure_subnets_v6() {
    echo ""
    read -rp "Configure IPv6 bypass subnets? (y/N): " -n 1 choice
    echo
    [[ ! "$choice" =~ ^[Yy]$ ]] && return

    local subnets=()
    while true; do
        read -rp "IPv6 subnet (or Enter to finish): " subnet
        [[ -z "$subnet" ]] && break

        if validate_ipv6_cidr "$subnet"; then
            subnets+=("$subnet")
            print_success "Added: $subnet"
        else
            print_error "Invalid IPv6 CIDR: $subnet"
        fi
    done

    if [[ ${#subnets[@]} -gt 0 ]]; then
        printf '"%s" ' "${subnets[@]}"
    fi
}

configure_vpn_interfaces() {
    print_info "Detecting VPN interfaces..."

    local detected=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && detected+=("$line")
    done < <(ip link show 2>/dev/null | grep -oP '(?<=: )(tun|tap|wg|ipsec|ppp|cscotun|tailscale|wg-|sdwan)\S+(?=:)' || true)

    if [[ ${#detected[@]} -gt 0 ]]; then
        echo "Detected interfaces: ${detected[*]}"
    else
        print_info "No VPN interfaces currently active"
    fi

    local interfaces=()
    echo "Enter VPN interface name(s), one per line."
    echo "Press Enter on empty line when done."
    echo ""

    while true; do
        read -rp "VPN interface (or Enter to finish) [default: tun0]: " iface
        if [[ -z "$iface" ]]; then
            [[ ${#interfaces[@]} -eq 0 ]] && interfaces=("tun0")
            break
        fi
        interfaces+=("$iface")
        print_success "Added: $iface"
    done

    printf '"%s" ' "${interfaces[@]}"
}

configure_optional_features() {
    local -A features
    echo ""
    echo -e "${BOLD}Optional Features:${NC}"
    echo ""

    # Route metric
    read -rp "Set route metric/priority? (y/N): " -n 1 choice; echo
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        read -rp "  Route metric (0-9999): " metric
        features[ROUTE_METRIC]="$metric"
    fi

    # Auto-discover
    read -rp "Auto-discover local subnets? (y/N): " -n 1 choice; echo
    [[ "$choice" =~ ^[Yy]$ ]] && features[AUTO_DISCOVER_SUBNETS]="true"

    # Connectivity verification
    read -rp "Verify connectivity after adding routes? (y/N): " -n 1 choice; echo
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        features[VERIFY_CONNECTIVITY]="true"
        echo "  Enter hosts to ping for verification (one per line, Enter to finish):"
        local hosts=()
        while true; do
            read -rp "  Host: " host
            [[ -z "$host" ]] && break
            hosts+=("$host")
        done
        if [[ ${#hosts[@]} -gt 0 ]]; then
            features[VERIFY_HOSTS]=$(printf '"%s" ' "${hosts[@]}")
        fi
    fi

    # Kill switch
    read -rp "Enable kill switch (block non-VPN traffic if VPN drops)? (y/N): " -n 1 choice; echo
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        features[KILL_SWITCH]="true"
        read -rp "  Backend — 1) iptables (default)  2) nftables: " -n 1 ks; echo
        [[ "$ks" == "2" ]] && features[KILL_SWITCH_BACKEND]="nftables"
    fi

    # DNS leak prevention
    read -rp "Enable DNS leak prevention? (y/N): " -n 1 choice; echo
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        features[DNS_LEAK_PREVENTION]="true"
        echo "  Enter direct DNS servers (one per line, Enter for gateway auto-detect):"
        local dns=()
        while true; do
            read -rp "  DNS server: " server
            [[ -z "$server" ]] && break
            dns+=("$server")
        done
        if [[ ${#dns[@]} -gt 0 ]]; then
            features[DIRECT_DNS_SERVERS]=$(printf '"%s" ' "${dns[@]}")
        fi
    fi

    # VPN-down cleanup
    read -rp "Remove routes on VPN disconnect? (y/N): " -n 1 choice; echo
    [[ "$choice" =~ ^[Yy]$ ]] && features[REMOVE_ROUTES_ON_VPN_DOWN]="true"

    # Desktop notifications
    read -rp "Enable desktop notifications? (y/N): " -n 1 choice; echo
    [[ "$choice" =~ ^[Yy]$ ]] && features[DESKTOP_NOTIFICATIONS]="true"

    # Return features as declarations
    for key in "${!features[@]}"; do
        echo "$key=${features[$key]}"
    done
}

# ============================================================================
# Create configuration file
# ============================================================================
create_config() {
    local tunnel_mode="$1"
    local subnets_v4="$2"
    local subnets_v6="$3"
    local vpn_interfaces="$4"
    shift 4
    local -a extra_features=("$@")

    print_info "Creating configuration file..."
    mkdir -p "$CONFIG_DIR"

    cat > "$CONFIG_FILE" << INNEREOF
# =============================================================================
# NetworkManager Split Tunnel Configuration
# Generated by setup.sh on $(date '+%Y-%m-%d %H:%M:%S')
# =============================================================================
# See split_tunnel.conf.example for full documentation of all options.

# Tunnel mode: "bypass" or "include"
TUNNEL_MODE="$tunnel_mode"

# IPv4 subnets
BYPASS_SUBNETS=($subnets_v4)

# IPv6 subnets
BYPASS_SUBNETS_V6=(${subnets_v6:-})

# VPN interface(s)
VPN_INTERFACES=($vpn_interfaces)

# Logging
ENABLE_LOGGING="true"
VERBOSE="false"

# Dry run (set to "true" to test without changes)
DRY_RUN="false"
INNEREOF

    # Append optional features
    for feat in "${extra_features[@]}"; do
        local key="${feat%%=*}"
        local val="${feat#*=}"
        case "$key" in
            VERIFY_HOSTS|DIRECT_DNS_SERVERS)
                echo "" >> "$CONFIG_FILE"
                echo "# $key" >> "$CONFIG_FILE"
                echo "${key}=(${val})" >> "$CONFIG_FILE"
                ;;
            *)
                echo "" >> "$CONFIG_FILE"
                echo "# $key" >> "$CONFIG_FILE"
                echo "${key}=\"${val}\"" >> "$CONFIG_FILE"
                ;;
        esac
    done

    chmod 640 "$CONFIG_FILE"
    print_success "Configuration saved to $CONFIG_FILE"
}

# ============================================================================
# Install script and extras
# ============================================================================
install_script() {
    print_info "Installing split tunnel script..."

    if [[ ! -f "$SCRIPT_NAME" ]]; then
        print_error "Script file $SCRIPT_NAME not found in current directory"
        exit 1
    fi

    mkdir -p "$(dirname "$INSTALL_PATH")"
    cp "$SCRIPT_NAME" "$INSTALL_PATH"
    chmod 755 "$INSTALL_PATH"

    # Log file
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"

    print_success "Script installed to $INSTALL_PATH"
}

install_logrotate() {
    if [[ -f "$LOGROTATE_SRC" ]]; then
        cp "$LOGROTATE_SRC" "$LOGROTATE_DST"
        chmod 644 "$LOGROTATE_DST"
        print_success "Logrotate config installed to $LOGROTATE_DST"
    else
        print_warning "Logrotate config not found at $LOGROTATE_SRC, skipping"
    fi
}

install_systemd_timer() {
    if [[ -f "$SYSTEMD_SERVICE_SRC" && -f "$SYSTEMD_TIMER_SRC" ]]; then
        cp "$SYSTEMD_SERVICE_SRC" "$SYSTEMD_SERVICE_DST"
        cp "$SYSTEMD_TIMER_SRC" "$SYSTEMD_TIMER_DST"
        systemctl daemon-reload
        systemctl enable split-tunnel-persist.timer
        systemctl start split-tunnel-persist.timer
        print_success "Systemd persistence timer installed and enabled"
    else
        print_warning "Systemd unit files not found, skipping persistence timer"
    fi
}

# ============================================================================
# Twingate relay bypass shim
# ============================================================================
build_twingate_shim() {
    print_info "Building Twingate relay bypass shim..."

    if [[ ! -f "$TWINGATE_SHIM_SRC" ]]; then
        print_error "C source not found: $TWINGATE_SHIM_SRC"
        print_info "Expected relative to setup.sh: src/twingate_no_binddev.c"
        return 1
    fi

    if ! command -v gcc &>/dev/null; then
        print_error "gcc not found — install build-essential: sudo apt install build-essential"
        return 1
    fi

    local tmp_so
    tmp_so=$(mktemp /tmp/twingate-no-binddev-XXXXXX.so)
    if gcc -shared -fPIC -o "$tmp_so" "$TWINGATE_SHIM_SRC" -ldl 2>&1; then
        install -m 644 "$tmp_so" "$TWINGATE_SHIM_DST"
        rm -f "$tmp_so"
        print_success "Shim installed to $TWINGATE_SHIM_DST"
        return 0
    else
        rm -f "$tmp_so"
        print_error "Compilation failed — see errors above"
        return 1
    fi
}

configure_twingate_proxy_setup() {
    echo ""
    echo -e "${BOLD}Twingate Relay Bypass (optional):${NC}"
    echo "  On restrictive networks (e.g., work WiFi) Twingate's relay ports"
    echo "  (30000-31000) may be blocked.  An LD_PRELOAD shim lets relay traffic"
    echo "  flow through ProtonVPN (or any always-on VPN) instead."
    echo "  Enable at work with: sudo $INSTALL_PATH twingate-proxy on"
    echo "  Disable at home with: sudo $INSTALL_PATH twingate-proxy off"
    echo ""
    read -rp "Set up Twingate relay bypass support? (y/N): " -n 1 choice; echo
    [[ ! "$choice" =~ ^[Yy]$ ]] && return 0

    if ! command -v gcc &>/dev/null; then
        print_error "gcc required — install with: sudo apt install build-essential"
        print_info "You can run 'sudo ./setup.sh build-shim' later once gcc is installed"
        return 1
    fi

    if build_twingate_shim; then
        # Write TWINGATE_PROXY_MODE=off into config (starts disabled; user enables at work)
        if [[ -f "$CONFIG_FILE" ]]; then
            if grep -q '^TWINGATE_PROXY_MODE=' "$CONFIG_FILE" 2>/dev/null; then
                sed -i 's|^TWINGATE_PROXY_MODE=.*|TWINGATE_PROXY_MODE="off"|' "$CONFIG_FILE"
            else
                printf '\n# Twingate relay bypass (toggle with: twingate-proxy on|off)\nTWINGATE_PROXY_MODE="off"\nTWINGATE_PROXY_PORT="8888"\n' >> "$CONFIG_FILE"
            fi
        fi
        echo ""
        print_success "Twingate relay bypass ready."
        print_info "At work  : sudo $INSTALL_PATH twingate-proxy on"
        print_info "At home  : sudo $INSTALL_PATH twingate-proxy off"
        print_info "Or use the aliases: twingate-work / twingate-home (after installing aliases)"
    fi
}

# ============================================================================
# Shell aliases
# ============================================================================
install_aliases() {
    print_info "Installing shell aliases to $ALIASES_FILE ..."
    cat > "$ALIASES_FILE" << 'ALIASEOF'
# split_tunnel_switch — convenience aliases
# Installed by setup.sh. Remove this file to uninstall.

# Manage split tunnel
alias st='sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel'
alias st-status='sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel status'
alias st-on='sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel add'
alias st-off='sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel remove'
alias st-reload='sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel reload'
alias st-log='tail -f /var/log/split_tunnel.log'

# Twingate relay bypass — enable when at work, disable at home
alias twingate-work='sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel twingate-proxy on'
alias twingate-home='sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel twingate-proxy off'
alias twingate-proxy-status='sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel twingate-proxy'
ALIASEOF
    chmod 644 "$ALIASES_FILE"
    print_success "Aliases installed to $ALIASES_FILE"
    print_info "Open a new shell or run: source $ALIASES_FILE"
    echo ""
    echo -e "  ${CYAN}Available aliases:${NC}"
    echo "    st               — run any split_tunnel command (e.g. st status)"
    echo "    st-status        — show split tunnel status"
    echo "    st-on            — add/restore split tunnel routes"
    echo "    st-off           — remove split tunnel routes"
    echo "    st-reload        — reload config and re-apply routes"
    echo "    st-log           — tail the split tunnel log"
    echo "    twingate-work    — enable relay bypass (use at work)"
    echo "    twingate-home    — disable relay bypass (use at home)"
    echo "    twingate-proxy-status — show current proxy mode"
    echo ""
}

remove_aliases() {
    if [[ -f "$ALIASES_FILE" ]]; then
        rm -f "$ALIASES_FILE"
        print_success "Removed $ALIASES_FILE"
    else
        print_info "No aliases file found at $ALIASES_FILE"
    fi
}

# ============================================================================
# Test / Apply / Status
# ============================================================================
test_installation() {
    print_info "Testing installation..."
    if "$INSTALL_PATH" test -v; then
        print_success "Test completed successfully"
        return 0
    else
        print_warning "Test completed with warnings"
        return 1
    fi
}

validate_installation() {
    print_info "Validating configuration..."
    "$INSTALL_PATH" validate
}

apply_routes() {
    print_info "Applying split tunnel routes..."
    if "$INSTALL_PATH" add; then
        print_success "Routes applied"
    else
        print_error "Failed to apply routes"
        return 1
    fi
}

show_status() {
    if [[ -x "$INSTALL_PATH" ]]; then
        "$INSTALL_PATH" status
    else
        print_error "Split tunnel script not installed"
    fi
}

# ============================================================================
# Uninstall
# ============================================================================
uninstall() {
    print_info "Uninstalling split tunnel..."

    # Remove routes + kill switch
    if [[ -x "$INSTALL_PATH" ]]; then
        print_info "Removing active routes and firewall rules..."
        "$INSTALL_PATH" remove 2>/dev/null || true
        "$INSTALL_PATH" kill-switch-off 2>/dev/null || true
    fi

    # Remove systemd timer
    if systemctl is-active --quiet split-tunnel-persist.timer 2>/dev/null; then
        systemctl stop split-tunnel-persist.timer
        systemctl disable split-tunnel-persist.timer
    fi
    rm -f "$SYSTEMD_SERVICE_DST" "$SYSTEMD_TIMER_DST"
    systemctl daemon-reload 2>/dev/null || true

    # Remove installed script
    rm -f "$INSTALL_PATH"
    print_success "Removed $INSTALL_PATH"

    # Remove Twingate shim and drop-in
    if [[ -f "$TWINGATE_DROP_IN" ]]; then
        rm -f "$TWINGATE_DROP_IN"
        systemctl daemon-reload 2>/dev/null || true
        print_success "Removed Twingate relay bypass drop-in"
    fi
    if [[ -f "$TWINGATE_SHIM_DST" ]]; then
        read -rp "Remove Twingate shim ($TWINGATE_SHIM_DST)? (y/n): " -n 1; echo
        [[ $REPLY =~ ^[Yy]$ ]] && rm -f "$TWINGATE_SHIM_DST" && print_success "Removed Twingate shim"
    fi

    # Remove aliases
    remove_aliases

    # Remove logrotate
    rm -f "$LOGROTATE_DST"

    # Ask about config and logs
    read -rp "Remove configuration, lock file, and logs? (y/n): " -n 1
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        rm -f "$LOG_FILE"
        rm -f /var/run/split_tunnel.lock
        print_success "Removed configuration and logs"
    fi

    print_success "Uninstallation complete"
}

# ============================================================================
# Interactive installation
# ============================================================================
interactive_install() {
    print_header
    check_root
    check_prerequisites
    backup_existing

    echo ""
    print_info "Starting interactive setup..."
    echo ""

    # Tunnel mode
    local tunnel_mode
    tunnel_mode=$(configure_tunnel_mode)

    # IPv4 subnets
    echo ""
    local subnets_v4
    subnets_v4=$(configure_subnets_v4)

    # IPv6 subnets
    local subnets_v6=""
    subnets_v6=$(configure_subnets_v6)

    # VPN interfaces
    echo ""
    local vpn_interfaces
    vpn_interfaces=$(configure_vpn_interfaces)

    # Optional features
    local -a feature_lines=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && feature_lines+=("$line")
    done < <(configure_optional_features)

    echo ""

    # Create config
    create_config "$tunnel_mode" "$subnets_v4" "$subnets_v6" "$vpn_interfaces" "${feature_lines[@]+"${feature_lines[@]}"}"

    # Install
    install_script
    install_logrotate
    install_systemd_timer

    echo ""
    print_info "Validating configuration..."
    validate_installation || true

    echo ""
    print_info "Testing configuration (dry run)..."
    test_installation || true

    # Twingate relay bypass (optional)
    configure_twingate_proxy_setup

    echo ""
    read -rp "Install shell aliases (twingate-work/twingate-home/st-status etc.)? (y/N): " -n 1; echo
    [[ $REPLY =~ ^[Yy]$ ]] && install_aliases

    echo ""
    read -rp "Apply routes now? (y/n): " -n 1
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        apply_routes
    fi

    echo ""
    print_success "Installation complete!"
    echo ""
    print_info "The script automatically runs on network/VPN events."
    print_info "Manual usage: sudo $INSTALL_PATH [add|remove|status|test|validate]"
    print_info ""
    print_info "Config file : $CONFIG_FILE"
    print_info "Log file    : $LOG_FILE"
    print_info "Full docs   : split_tunnel.conf.example"
    echo ""
}

# ============================================================================
# Quick install
# ============================================================================
quick_install() {
    print_header
    print_info "Quick installation with default settings..."

    check_root
    check_prerequisites
    backup_existing

    create_config "bypass" '"192.168.1.0/24" "192.168.2.0/24"' "" '"tun0"'
    install_script
    install_logrotate
    install_systemd_timer

    print_success "Installation complete!"
    print_info "Edit $CONFIG_FILE to customize — see split_tunnel.conf.example for all options"
}

# ============================================================================
# Run tests
# ============================================================================
# shellcheck disable=SC2120
run_tests() {
    if [[ -x "$TEST_SCRIPT" ]]; then
        exec bash "$TEST_SCRIPT" "$@"
    else
        print_error "Test script not found at $TEST_SCRIPT"
        exit 1
    fi
}

# ============================================================================
# Main menu
# ============================================================================
show_menu() {
    print_header
    echo "  1) Interactive installation"
    echo "  2) Quick install (with defaults)"
    echo "  3) Uninstall"
    echo "  4) Show status"
    echo "  5) Validate configuration"
    echo "  6) Test configuration (dry run)"
    echo "  7) Apply routes now"
    echo "  8) Remove routes now"
    echo "  9) Run test suite"
    echo "  t) Build Twingate relay bypass shim"
    echo "  a) Install shell aliases"
    echo "  0) Exit"
    echo ""
    read -rp "Select an option: " -n 1
    echo

    case $REPLY in
        1) interactive_install ;;
        2) check_root; quick_install ;;
        3) check_root; uninstall ;;
        4) show_status ;;
        5) check_root; [[ -x "$INSTALL_PATH" ]] && validate_installation || print_error "Not installed" ;;
        6) check_root; [[ -x "$INSTALL_PATH" ]] && "$INSTALL_PATH" test -v || print_error "Not installed" ;;
        7) check_root; [[ -x "$INSTALL_PATH" ]] && apply_routes || print_error "Not installed" ;;
        8) check_root; [[ -x "$INSTALL_PATH" ]] && "$INSTALL_PATH" remove || print_error "Not installed" ;;
        9) run_tests ;;
        t|T) check_root; build_twingate_shim ;;
        a|A) check_root; install_aliases ;;
        0) exit 0 ;;
        *) print_error "Invalid option"; exit 1 ;;
    esac
}

# ============================================================================
# CLI entry
# ============================================================================
if [[ $# -eq 0 ]]; then
    show_menu
else
    case "$1" in
        install)          check_root; interactive_install ;;
        quick-install)    check_root; quick_install ;;
        uninstall)        check_root; uninstall ;;
        status)           show_status ;;
        validate)         check_root; [[ -x "$INSTALL_PATH" ]] && validate_installation || print_error "Not installed" ;;
        test)             check_root; [[ -x "$INSTALL_PATH" ]] && "$INSTALL_PATH" test -v || print_error "Not installed" ;;
        run-tests)        run_tests ;;
        build-shim)       check_root; build_twingate_shim ;;
        install-aliases)  check_root; install_aliases ;;
        twingate-proxy)
            check_root
            if [[ -z "${2:-}" ]]; then
                echo "Twingate relay bypass shim: $([ -f "$TWINGATE_SHIM_DST" ] && echo 'installed' || echo 'NOT installed')"
                echo "Systemd drop-in active:     $([ -f "$TWINGATE_DROP_IN" ] && echo 'yes' || echo 'no')"
                echo "Usage: $0 twingate-proxy [on|off]"
            else
                [[ -x "$INSTALL_PATH" ]] && "$INSTALL_PATH" twingate-proxy "${2}" || print_error "split_tunnel not installed"
            fi
            ;;
        *)
            echo "Usage: $0 [install|quick-install|uninstall|status|validate|test|run-tests]"
            echo "       $0 build-shim          # compile Twingate relay bypass shim"
            echo "       $0 install-aliases      # install shell aliases"
            echo "       $0 twingate-proxy [on|off]  # toggle relay bypass"
            echo "  Or run without arguments for interactive menu"
            exit 1
            ;;
    esac
fi
