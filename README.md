# NetworkManager Split Tunneling Script

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Version](https://img.shields.io/badge/Version-3.0.0-orange.svg)](CHANGELOG.md)

A robust, feature-rich split tunneling solution for Linux systems using NetworkManager. Route specific subnets outside (or exclusively through) your VPN connection with full IPv4/IPv6 support, a kill switch, DNS leak prevention, and more.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Tunnel Modes](#tunnel-modes)
- [Advanced Features](#advanced-features)
- [How It Works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Test Suite](#test-suite)
- [Contributing](#contributing)
- [License](#license)

## Overview

This script enables **split tunneling** by managing routes so that specific subnets bypass a VPN connection (or, in include mode, so that only specific subnets use the VPN). It integrates with NetworkManager's dispatcher system to automatically adjust routes on network and VPN events.

### Use Cases

- Access local network devices (NAS, printers, IoT) while connected to a VPN
- Route specific subnets through your ISP for better performance
- Corporate VPN setups where only work resources need the tunnel (include mode)
- Maintain access to home automation systems during VPN sessions
- Prevent DNS leaks when accessing local services
- Block traffic leaks if the VPN connection drops (kill switch)

## Features

### Core
- **Dual-stack routing**: Full IPv4 and IPv6 support
- **Two tunnel modes**: *Bypass* (subnets skip VPN) and *Include* (only listed subnets use VPN)
- **Multiple VPN interfaces**: Simultaneous support for OpenVPN + WireGuard + others
- **Safe config parsing**: Configuration is parsed line-by-line — never `source`d or `eval`'d
- **Route metrics**: Fine-grained control over routing priority

### Security
- **Kill switch**: Block all non-VPN traffic via iptables or nftables if the VPN drops
- **DNS leak prevention**: Route DNS queries for specified servers through the physical gateway
- **Strict config permissions**: Warns if the config file is world-writable

### Reliability
- **Route persistence**: Systemd timer periodically verifies and re-applies routes
- **Lock file protection**: Prevents race conditions from concurrent dispatcher calls
- **Connectivity verification**: Optional post-route ping checks with notifications
- **Automatic local subnet discovery**: Detects LAN subnets from physical interfaces

### Operations
- **Log rotation**: Ships with a logrotate config for `/var/log/split_tunnel.log`
- **Verbose/debug mode**: `-v` flag for detailed diagnostic output
- **Config validation**: `validate` command checks config without modifying routes
- **Dry-run mode**: `test` command shows what would happen
- **Desktop notifications**: Optional notify-send integration
- **VPN-down cleanup**: Configurable automatic route removal on VPN disconnect
- **Interactive setup wizard**: Step-by-step installation with all features
- **Clean uninstall**: Removes scripts, configs, firewall rules, and systemd units

## Requirements

- **OS**: Linux with NetworkManager
- **Shell**: Bash 4.0+
- **Utilities**: `ip`, `awk`, `grep`, `systemctl`, `ping`
- **Permissions**: Root/sudo access

### Optional Dependencies

| Feature | Requires |
|---------|----------|
| Kill switch (iptables) | `iptables`, `ip6tables` |
| Kill switch (nftables) | `nft` |
| Desktop notifications | `notify-send` (libnotify) |
| Linting tests | `shellcheck` |

### Tested On

- Ubuntu 20.04+ / 22.04 / 24.04
- Debian 10+ / 11 / 12
- Fedora 33+
- Arch Linux
- Linux Mint 20+
- Pop!_OS 22.04+
- Tuxedo OS

## Quick Start

```bash
# Clone the repository
git clone https://github.com/ChiefGyk3D/split_tunnel_switch.git
cd split_tunnel_switch

# Run the interactive setup
sudo bash setup.sh
```

The setup wizard guides you through configuring subnets, VPN interfaces, and all optional features.

For a fast install with defaults:

```bash
sudo bash setup.sh quick-install
# Then customize /etc/split_tunnel/split_tunnel.conf
```

See [QUICKSTART.md](QUICKSTART.md) for a 5-minute getting-started guide.

## Installation

### Method 1: Interactive Setup (Recommended)

```bash
chmod +x setup.sh
sudo ./setup.sh install
```

### Method 2: Quick Install

```bash
sudo ./setup.sh quick-install
sudo nano /etc/split_tunnel/split_tunnel.conf
```

### Method 3: Manual Installation

```bash
# 1. Install the dispatcher script
sudo mkdir -p /etc/NetworkManager/dispatcher.d
sudo cp split_tunnel.sh /etc/NetworkManager/dispatcher.d/99-split-tunnel
sudo chmod 755 /etc/NetworkManager/dispatcher.d/99-split-tunnel

# 2. Create configuration
sudo mkdir -p /etc/split_tunnel
sudo cp split_tunnel.conf.example /etc/split_tunnel/split_tunnel.conf
sudo chmod 640 /etc/split_tunnel/split_tunnel.conf
sudo nano /etc/split_tunnel/split_tunnel.conf

# 3. Create log file
sudo touch /var/log/split_tunnel.log
sudo chmod 644 /var/log/split_tunnel.log

# 4. Install logrotate config (optional)
sudo cp extras/logrotate.d/split_tunnel /etc/logrotate.d/split_tunnel

# 5. Install persistence timer (optional)
sudo cp extras/systemd/split-tunnel-persist.service /etc/systemd/system/
sudo cp extras/systemd/split-tunnel-persist.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now split-tunnel-persist.timer

# 6. Validate and apply
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel validate
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel add
```

## Configuration

### Configuration File

Edit `/etc/split_tunnel/split_tunnel.conf`. See [split_tunnel.conf.example](split_tunnel.conf.example) for full documentation of every option.

### Essential Settings

```bash
# Tunnel mode: "bypass" or "include"
TUNNEL_MODE="bypass"

# IPv4 subnets to bypass VPN
BYPASS_SUBNETS=("192.168.1.0/24" "192.168.2.0/24")

# IPv6 subnets to bypass VPN
BYPASS_SUBNETS_V6=("fd00::/48")

# VPN interface(s)
VPN_INTERFACES=("tun0")
```

### Security Settings

```bash
# Kill switch — block leaks if VPN drops
KILL_SWITCH="true"
KILL_SWITCH_BACKEND="iptables"   # or "nftables"

# DNS leak prevention
DNS_LEAK_PREVENTION="true"
DIRECT_DNS_SERVERS=("192.168.1.1")
```

### Operational Settings

```bash
# Route priority (lower = higher priority)
ROUTE_METRIC="100"

# Auto-discover LAN subnets
AUTO_DISCOVER_SUBNETS="true"

# Verify connectivity after route changes
VERIFY_CONNECTIVITY="true"
VERIFY_HOSTS=("192.168.1.1" "192.168.1.100")

# Clean up routes on VPN disconnect
REMOVE_ROUTES_ON_VPN_DOWN="true"

# Desktop notifications
DESKTOP_NOTIFICATIONS="true"

# Verbose logging
VERBOSE="false"
```

### Common Subnet Examples

```bash
# Home network
BYPASS_SUBNETS=("192.168.1.0/24")

# Multiple networks (home + office + IoT)
BYPASS_SUBNETS=("192.168.1.0/24" "192.168.2.0/24" "10.0.0.0/24")

# All RFC-1918 private ranges
BYPASS_SUBNETS=("10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16")

# Specific device
BYPASS_SUBNETS=("192.168.1.100/32")
```

### VPN Interface Names

| VPN Provider / Type | Common Interface |
|---------------------|------------------|
| OpenVPN | `tun0`, `tap0` |
| WireGuard | `wg0` |
| IPsec / IKEv2 | `ipsec0` |
| PPTP | `ppp0` |
| Cisco AnyConnect | `cscotun0` |
| Tailscale | `tailscale0` |
| Mullvad | `wg-mullvad` |

## Usage

### Automatic Mode

Once installed in `/etc/NetworkManager/dispatcher.d/`, the script automatically runs when:
- A network connection is established (`up`)
- A VPN connection starts (`vpn-up`)
- A VPN connection stops (`vpn-down`) — cleanup if configured

### Manual Commands

```bash
SCRIPT="/etc/NetworkManager/dispatcher.d/99-split-tunnel"

# Add split tunnel routes
sudo $SCRIPT add

# Remove all routes and firewall rules
sudo $SCRIPT remove

# Reload (remove + re-read config + re-apply)
sudo $SCRIPT reload

# Show current status
sudo $SCRIPT status

# Dry-run test
sudo $SCRIPT test

# Validate configuration
sudo $SCRIPT validate

# Discover local subnets
sudo $SCRIPT discover

# Verbose output
sudo $SCRIPT add -v

# Use alternate config
sudo $SCRIPT -c /path/to/config.conf add

# Kill switch manual control
sudo $SCRIPT kill-switch-on
sudo $SCRIPT kill-switch-off

# Show version
sudo $SCRIPT version

# Show help
sudo $SCRIPT help
```

### Setup Script

```bash
sudo ./setup.sh               # Interactive menu
sudo ./setup.sh install        # Interactive installation
sudo ./setup.sh quick-install  # Install with defaults
sudo ./setup.sh uninstall      # Clean uninstall
sudo ./setup.sh status         # Show status
sudo ./setup.sh validate       # Validate config
sudo ./setup.sh test           # Dry-run
sudo ./setup.sh run-tests      # Run test suite
```

## Tunnel Modes

### Bypass Mode (Default)

Listed subnets bypass the VPN. All other traffic goes through the VPN.

```
Internet traffic  ──→  VPN tunnel  ──→  VPN server  ──→  Internet
Local traffic     ──→  Physical gateway  ──→  LAN devices
```

Best for: accessing local devices while VPN is active.

### Include Mode

ONLY listed subnets go through the VPN. Everything else uses the physical gateway.

```
Work resources    ──→  VPN tunnel  ──→  Corporate network
Everything else   ──→  Physical gateway  ──→  Internet (direct)
```

Best for: corporate VPNs where only work resources need the tunnel.

## Advanced Features

### Kill Switch

Blocks all outgoing traffic that doesn't go through the VPN or to a bypass subnet. Prevents accidental data leaks if the VPN connection drops.

Allowed traffic:
- VPN interfaces (all configured)
- Bypass subnets (IPv4 + IPv6)
- Loopback
- Established connections
- DHCP (ports 67-68)
- Direct DNS servers (if DNS leak prevention enabled)

```bash
# Enable in config
KILL_SWITCH="true"
KILL_SWITCH_BACKEND="iptables"  # or "nftables"

# Manual control
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel kill-switch-on
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel kill-switch-off
```

### DNS Leak Prevention

Routes DNS queries through the physical gateway for specified servers, preventing DNS from leaking through the VPN when accessing local resources.

```bash
DNS_LEAK_PREVENTION="true"
DIRECT_DNS_SERVERS=("192.168.1.1" "1.1.1.1")
```

### Route Persistence

The systemd timer periodically re-applies routes to catch cases where VPN clients overwrite them. Installed automatically by `setup.sh`.

```bash
# Check timer status
systemctl status split-tunnel-persist.timer

# View timer schedule
systemctl list-timers split-tunnel-persist.timer

# Manually trigger
systemctl start split-tunnel-persist.service
```

### Auto-Discovery

Automatically detects subnets on physical (non-VPN) network interfaces and adds them to the bypass list.

```bash
# Enable in config
AUTO_DISCOVER_SUBNETS="true"

# Or run manually
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel discover
```

### Connectivity Verification

After adding routes, pings specified hosts to confirm reachability. Sends a desktop notification if any host is unreachable.

```bash
VERIFY_CONNECTIVITY="true"
VERIFY_HOSTS=("192.168.1.1" "nas.local")
```

## How It Works

```
┌──────────────────────────────────────────┐
│              Network Event               │
│  (up / vpn-up / vpn-down / interface)    │
└─────────────────┬────────────────────────┘
                  │
    ┌─────────────▼──────────────┐
    │   NetworkManager Dispatcher │
    │   99-split-tunnel           │
    └─────────────┬──────────────┘
                  │
    ┌─────────────▼──────────────┐
    │   Load Config (safe parse) │
    │   Validate settings        │
    └─────────────┬──────────────┘
                  │
    ┌─────────────▼──────────────┐
    │   Auto-discover subnets?   │──── Yes ──→ Scan interfaces
    └─────────────┬──────────────┘
                  │
    ┌─────────────▼──────────────┐
    │   Add routes (IPv4 + IPv6) │
    │   + metric if configured   │
    └─────────────┬──────────────┘
                  │
    ┌─────────────▼──────────────┐
    │   DNS leak prevention?     │──── Yes ──→ Add /32 DNS routes
    └─────────────┬──────────────┘
                  │
    ┌─────────────▼──────────────┐
    │   Kill switch?             │──── Yes ──→ Apply firewall rules
    └─────────────┬──────────────┘
                  │
    ┌─────────────▼──────────────┐
    │   Verify connectivity?     │──── Yes ──→ Ping hosts
    └─────────────┬──────────────┘
                  │
    ┌─────────────▼──────────────┐
    │   Send notification?       │──── Yes ──→ notify-send
    └─────────────┬──────────────┘
                  │
    ┌─────────────▼──────────────┐
    │   Log results + release    │
    │   lock file                │
    └────────────────────────────┘
```

## Verification

### Check Active Routes

```bash
# IPv4 routes
ip -4 route show

# IPv6 routes
ip -6 route show

# Check specific subnet
ip route show 192.168.1.0/24

# Full status
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel status
```

### Expected Output (bypass mode)

```
default via 10.8.0.1 dev tun0 proto static metric 50
192.168.1.0/24 via 192.168.0.1 dev eth0 metric 100    ← Bypass route
192.168.2.0/24 via 192.168.0.1 dev eth0 metric 100    ← Bypass route
10.8.0.0/24 dev tun0 proto kernel scope link
```

### Check Logs

```bash
# Live log tailing
tail -f /var/log/split_tunnel.log

# Errors only
grep ERROR /var/log/split_tunnel.log

# Today's entries
grep "$(date +%Y-%m-%d)" /var/log/split_tunnel.log
```

## Troubleshooting

### Routes Not Applied

```bash
# 1. Check NetworkManager is running
systemctl status NetworkManager

# 2. Verify script permissions
ls -la /etc/NetworkManager/dispatcher.d/99-split-tunnel

# 3. Check logs
tail -30 /var/log/split_tunnel.log

# 4. Validate config
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel validate

# 5. Run manually with verbose output
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel add -v
```

### VPN Interface Not Found

```bash
# List all network interfaces
ip link show

# Check for VPN interfaces
ip link show | grep -E 'tun|wg|tap|ipsec|ppp'

# Update config
sudo nano /etc/split_tunnel/split_tunnel.conf
```

### Kill Switch Blocking Traffic

```bash
# Check if kill switch is active
sudo iptables -L SPLIT_TUNNEL_KS 2>/dev/null
# or
sudo nft list table inet split_tunnel_killswitch 2>/dev/null

# Disable kill switch
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel kill-switch-off

# Or remove everything
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel remove
```

### Routes Disappear After VPN Reconnect

```bash
# 1. Enable the persistence timer
sudo systemctl enable --now split-tunnel-persist.timer

# 2. Check timer status
systemctl list-timers split-tunnel-persist.timer

# 3. Enable vpn-down cleanup + re-add
# Set REMOVE_ROUTES_ON_VPN_DOWN="true" in config
```

### Lock File Issues

```bash
# Remove stale lock
sudo rm -f /var/run/split_tunnel.lock

# Check for hung processes
ps aux | grep split_tunnel
```

### DNS Leaks

```bash
# 1. Enable DNS leak prevention
# DNS_LEAK_PREVENTION="true" in config

# 2. Check DNS routing
ip route show | grep '/32'

# 3. Test DNS resolution
nslookup example.com
dig example.com
```

## FAQ

**Q: Will this work with my VPN client?**
A: Yes — it works with any VPN that creates a network interface (OpenVPN, WireGuard, IPsec, Cisco AnyConnect, Tailscale, etc.).

**Q: Can I use multiple VPNs simultaneously?**
A: Yes. List all VPN interfaces in `VPN_INTERFACES=("tun0" "wg0")`.

**Q: Does this affect VPN security?**
A: Traffic to bypass subnets goes through your regular connection. Only configure trusted local networks. Enable the kill switch for extra protection.

**Q: What's the difference between bypass and include mode?**
A: *Bypass* = listed subnets skip VPN (default). *Include* = only listed subnets use VPN, everything else is direct.

**Q: Can I add/remove subnets without reinstalling?**
A: Yes. Edit `/etc/split_tunnel/split_tunnel.conf` and run `sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel add`.

**Q: How do I temporarily disable everything?**
A: Run `sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel remove`.

**Q: Does the kill switch persist across reboots?**
A: The kill switch is re-applied by the systemd persistence timer and on VPN-up events. It is not persistent in iptables/nftables between reboots on its own.

**Q: Is the configuration file safe?**
A: Yes — the config file is parsed line-by-line. Values are never `source`'d or `eval`'d. Only recognized keys are accepted.

## Test Suite

Run the included test suite to verify your installation:

```bash
# All tests
./tests/run_tests.sh

# Lint only (requires shellcheck)
./tests/run_tests.sh lint

# Unit tests only
./tests/run_tests.sh unit

# Integration tests (requires root)
sudo ./tests/run_tests.sh integration
```

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

```bash
git clone https://github.com/ChiefGyk3D/split_tunnel_switch.git
cd split_tunnel_switch
git checkout -b feature/your-feature
# Make changes, run tests
./tests/run_tests.sh
git commit -am "feat: your feature"
git push origin feature/your-feature
```

## License

This project is licensed under the GNU General Public License v3.0 — see [LICENSE](LICENSE).

## Support

- **Issues**: [GitHub Issues](https://github.com/ChiefGyk3D/split_tunnel_switch/issues)
- **Discussions**: [GitHub Discussions](https://github.com/ChiefGyk3D/split_tunnel_switch/discussions)

---

**Made with care for the Linux community**
