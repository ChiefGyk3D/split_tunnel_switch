#!/bin/bash
# NetworkManager Split Tunnel Setup Script
# Interactive installation and configuration tool

set -euo pipefail

# Configuration paths
SCRIPT_NAME="split_tunnel.sh"
INSTALL_PATH="/etc/NetworkManager/dispatcher.d/99-split-tunnel"
CONFIG_DIR="/etc/split_tunnel"
CONFIG_FILE="$CONFIG_DIR/split_tunnel.conf"
LOG_FILE="/var/log/split_tunnel.log"
SYSTEMD_SERVICE="/etc/systemd/system/split-tunnel.service"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

print_header() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  NetworkManager Split Tunnel Setup${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    local missing_deps=()
    
    # Check for required commands
    for cmd in ip awk grep systemctl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        exit 1
    fi
    
    # Check if NetworkManager is installed and running
    if ! systemctl is-active --quiet NetworkManager; then
        print_warning "NetworkManager is not running"
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    print_success "All prerequisites met"
}

# Backup existing installation
backup_existing() {
    if [[ -f "$INSTALL_PATH" ]]; then
        local backup_path="${INSTALL_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
        print_info "Backing up existing installation to $backup_path"
        cp "$INSTALL_PATH" "$backup_path"
    fi
    
    if [[ -f "$CONFIG_FILE" ]]; then
        local backup_path="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        print_info "Backing up existing config to $backup_path"
        cp "$CONFIG_FILE" "$backup_path"
    fi
}

# Configure subnets interactively
configure_subnets() {
    print_info "Configuring bypass subnets..."
    echo "Enter the subnets that should bypass the VPN (one per line)"
    echo "Press Enter on empty line when done. Examples:"
    echo "  192.168.1.0/24"
    echo "  10.0.0.0/8"
    echo ""
    
    local subnets=()
    while true; do
        read -p "Subnet (or press Enter to finish): " subnet
        if [[ -z "$subnet" ]]; then
            if [[ ${#subnets[@]} -eq 0 ]]; then
                print_warning "No subnets entered, using defaults"
                subnets=("192.168.1.0/24" "192.168.2.0/24")
            fi
            break
        fi
        
        # Basic validation
        if [[ $subnet =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
            subnets+=("$subnet")
            print_success "Added: $subnet"
        else
            print_error "Invalid subnet format. Use CIDR notation (e.g., 192.168.1.0/24)"
        fi
    done
    
    echo "${subnets[@]}"
}

# Configure VPN interface
configure_vpn_interface() {
    print_info "Detecting VPN interfaces..."
    
    # Try to detect VPN interfaces
    local vpn_interfaces=($(ip link show | grep -E 'tun|tap|wg' | awk -F: '{print $2}' | tr -d ' '))
    
    if [[ ${#vpn_interfaces[@]} -gt 0 ]]; then
        echo "Detected VPN interfaces: ${vpn_interfaces[*]}"
        read -p "Enter VPN interface name [default: tun0]: " vpn_interface
        vpn_interface=${vpn_interface:-tun0}
    else
        print_warning "No VPN interfaces detected"
        read -p "Enter VPN interface name [default: tun0]: " vpn_interface
        vpn_interface=${vpn_interface:-tun0}
    fi
    
    echo "$vpn_interface"
}

# Create configuration file
create_config() {
    local subnets_str="$1"
    local vpn_interface="$2"
    
    print_info "Creating configuration file..."
    
    mkdir -p "$CONFIG_DIR"
    
    cat > "$CONFIG_FILE" << EOF
# NetworkManager Split Tunnel Configuration
# This file is sourced by the split_tunnel.sh script

# Define the subnets that should bypass the VPN
# Format: BYPASS_SUBNETS=("subnet1" "subnet2" ...)
BYPASS_SUBNETS=($subnets_str)

# VPN interface to exclude from routing
# Common values: tun0, tap0, wg0
VPN_INTERFACE="$vpn_interface"

# Enable logging to $LOG_FILE
ENABLE_LOGGING="true"

# Dry run mode (for testing without making changes)
DRY_RUN="false"
EOF
    
    chmod 644 "$CONFIG_FILE"
    print_success "Configuration saved to $CONFIG_FILE"
}

# Install the script
install_script() {
    print_info "Installing split tunnel script..."
    
    if [[ ! -f "$SCRIPT_NAME" ]]; then
        print_error "Script file $SCRIPT_NAME not found in current directory"
        exit 1
    fi
    
    # Create dispatcher directory if it doesn't exist
    mkdir -p "$(dirname "$INSTALL_PATH")"
    
    # Copy script
    cp "$SCRIPT_NAME" "$INSTALL_PATH"
    chmod 755 "$INSTALL_PATH"
    
    # Create log file with proper permissions
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    print_success "Script installed to $INSTALL_PATH"
}

# Test the installation
test_installation() {
    print_info "Testing installation..."
    
    if ! "$INSTALL_PATH" test; then
        print_warning "Test mode completed with warnings. Check output above."
        return 1
    fi
    
    print_success "Test completed successfully"
    return 0
}

# Apply routes immediately
apply_routes() {
    print_info "Applying split tunnel routes..."
    
    if "$INSTALL_PATH" add; then
        print_success "Split tunnel routes applied"
        return 0
    else
        print_error "Failed to apply routes"
        return 1
    fi
}

# Show status
show_status() {
    if [[ -x "$INSTALL_PATH" ]]; then
        "$INSTALL_PATH" status
    else
        print_error "Split tunnel script not installed"
    fi
}

# Uninstall
uninstall() {
    print_info "Uninstalling split tunnel..."
    
    # Remove routes if script exists
    if [[ -x "$INSTALL_PATH" ]]; then
        print_info "Removing active routes..."
        "$INSTALL_PATH" remove || true
    fi
    
    # Remove installed files
    if [[ -f "$INSTALL_PATH" ]]; then
        rm -f "$INSTALL_PATH"
        print_success "Removed $INSTALL_PATH"
    fi
    
    # Ask about config and logs
    read -p "Remove configuration and logs? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        rm -f "$LOG_FILE"
        print_success "Removed configuration and logs"
    fi
    
    print_success "Uninstallation complete"
}

# Interactive installation
interactive_install() {
    print_header
    
    check_root
    check_prerequisites
    backup_existing
    
    echo ""
    print_info "Starting interactive setup..."
    echo ""
    
    # Get subnets
    local subnets
    IFS=' ' read -ra subnets_array <<< "$(configure_subnets)"
    local subnets_str=$(printf '"%s" ' "${subnets_array[@]}")
    
    echo ""
    
    # Get VPN interface
    local vpn_interface=$(configure_vpn_interface)
    
    echo ""
    
    # Create configuration
    create_config "$subnets_str" "$vpn_interface"
    
    # Install script
    install_script
    
    echo ""
    print_info "Testing configuration..."
    if test_installation; then
        echo ""
        read -p "Apply routes now? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            apply_routes
        fi
    fi
    
    echo ""
    print_success "Installation complete!"
    echo ""
    print_info "The script will automatically run when network changes occur."
    print_info "You can also run it manually with: sudo $INSTALL_PATH [add|remove|status]"
    print_info ""
    print_info "Configuration file: $CONFIG_FILE"
    print_info "Log file: $LOG_FILE"
    echo ""
}

# Quick install with defaults
quick_install() {
    print_header
    print_info "Quick installation with default settings..."
    
    check_root
    check_prerequisites
    backup_existing
    
    local subnets_str='"192.168.1.0/24" "192.168.2.0/24"'
    local vpn_interface="tun0"
    
    create_config "$subnets_str" "$vpn_interface"
    install_script
    
    print_success "Installation complete!"
    print_info "Edit $CONFIG_FILE to customize subnets"
}

# Main menu
show_menu() {
    print_header
    echo "1) Interactive installation"
    echo "2) Quick install (with defaults)"
    echo "3) Uninstall"
    echo "4) Show status"
    echo "5) Test configuration"
    echo "6) Apply routes now"
    echo "7) Remove routes now"
    echo "8) Exit"
    echo ""
    read -p "Select an option [1-8]: " -n 1 -r
    echo
    
    case $REPLY in
        1)
            interactive_install
            ;;
        2)
            quick_install
            ;;
        3)
            check_root
            uninstall
            ;;
        4)
            show_status
            ;;
        5)
            check_root
            if [[ -x "$INSTALL_PATH" ]]; then
                "$INSTALL_PATH" test
            else
                print_error "Not installed. Run installation first."
            fi
            ;;
        6)
            check_root
            if [[ -x "$INSTALL_PATH" ]]; then
                apply_routes
            else
                print_error "Not installed. Run installation first."
            fi
            ;;
        7)
            check_root
            if [[ -x "$INSTALL_PATH" ]]; then
                "$INSTALL_PATH" remove
            else
                print_error "Not installed. Run installation first."
            fi
            ;;
        8)
            exit 0
            ;;
        *)
            print_error "Invalid option"
            exit 1
            ;;
    esac
}

# Handle command line arguments
if [[ $# -eq 0 ]]; then
    show_menu
else
    case "$1" in
        install)
            check_root
            interactive_install
            ;;
        quick-install)
            check_root
            quick_install
            ;;
        uninstall)
            check_root
            uninstall
            ;;
        status)
            show_status
            ;;
        *)
            echo "Usage: $0 [install|quick-install|uninstall|status]"
            echo "  Or run without arguments for interactive menu"
            exit 1
            ;;
    esac
fi
