# NetworkManager Split Tunneling Script

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)

A robust and feature-rich split tunneling solution for Linux systems using NetworkManager. Route specific subnets outside your VPN connection while keeping other traffic secure.

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [How It Works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Contributing](#contributing)
- [License](#license)

## 🔍 Overview

This script enables **split tunneling** by allowing specified subnets to bypass a VPN connection. Perfect for accessing local network resources (printers, NAS, IoT devices) while connected to a VPN.

### Use Cases

- Access local network devices while connected to a corporate VPN
- Route specific subnets through your ISP for better performance
- Maintain access to home automation systems during VPN sessions
- Bypass VPN for trusted local services while securing internet traffic

## ✨ Features

- **🔄 Automatic Operation**: Integrates with NetworkManager dispatcher for automatic route management
- **🎯 Flexible Configuration**: Easy-to-edit configuration file for subnet management
- **📝 Comprehensive Logging**: Detailed logging with timestamps for troubleshooting
- **🔒 Safe Execution**: Lock file mechanism prevents concurrent runs
- **🧪 Dry Run Mode**: Test configuration changes without modifying routes
- **📊 Status Monitoring**: Check current split tunnel status and active routes
- **⚙️ Multiple VPN Support**: Works with OpenVPN, WireGuard, IPsec, and more
- **🎨 Color-Coded Output**: Clear, readable terminal output with status indicators
- **🔧 Interactive Setup**: Easy installation wizard with step-by-step guidance
- **♻️ Clean Uninstall**: Complete removal including configuration and logs

## � Requirements

- **OS**: Linux (any distribution with NetworkManager)
- **Network Manager**: NetworkManager service running
- **Shell**: Bash 4.0+
- **Utilities**: `ip`, `awk`, `grep`, `systemctl` (standard on most Linux systems)
- **Permissions**: Root/sudo access for installation and route modification

### Tested On

- Ubuntu 20.04+
- Debian 10+
- Fedora 33+
- Arch Linux
- Linux Mint 20+

## 🚀 Quick Start

### Easy Installation (Recommended)

```bash
# Clone or download the repository
git clone https://github.com/ChiefGyk3D/split_tunnel_switch.git
cd split_tunnel_switch

# Run the interactive setup
sudo bash setup.sh
```

The setup wizard will guide you through:
1. Configuring bypass subnets
2. Selecting your VPN interface
3. Installing the script
4. Testing the configuration

### Quick Install with Defaults

For a fast setup with default settings:

```bash
sudo bash setup.sh quick-install
```

Then edit `/etc/split_tunnel/split_tunnel.conf` to customize your subnets.

## 🛠️ Installation

### Method 1: Interactive Setup (Recommended)

```bash
# Make setup script executable
chmod +x setup.sh

# Run interactive installation
sudo ./setup.sh install
```

### Method 2: Manual Installation

```bash
# 1. Copy the main script
sudo mkdir -p /etc/NetworkManager/dispatcher.d
sudo cp split_tunnel.sh /etc/NetworkManager/dispatcher.d/99-split-tunnel
sudo chmod +x /etc/NetworkManager/dispatcher.d/99-split-tunnel

# 2. Create configuration directory and file
sudo mkdir -p /etc/split_tunnel
sudo cp split_tunnel.conf.example /etc/split_tunnel/split_tunnel.conf

# 3. Edit configuration (customize your subnets)
sudo nano /etc/split_tunnel/split_tunnel.conf

# 4. Create log file
sudo touch /var/log/split_tunnel.log
sudo chmod 644 /var/log/split_tunnel.log

# 5. Test the configuration
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel test

# 6. Apply routes
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel add
```

## ⚙️ Configuration

### Configuration File

Edit `/etc/split_tunnel/split_tunnel.conf`:

```bash
# Define subnets to bypass VPN
BYPASS_SUBNETS=("192.168.1.0/24" "192.168.2.0/24" "10.0.0.0/24")

# Your VPN interface (tun0, wg0, etc.)
VPN_INTERFACE="tun0"

# Enable logging
ENABLE_LOGGING="true"

# Dry run mode (test without changes)
DRY_RUN="false"
```

### Common Subnet Examples

```bash
# Home network
BYPASS_SUBNETS=("192.168.1.0/24")

# Multiple networks
BYPASS_SUBNETS=("192.168.1.0/24" "192.168.2.0/24" "10.0.0.0/24")

# Entire private ranges
BYPASS_SUBNETS=("10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16")

# Specific device
BYPASS_SUBNETS=("192.168.1.100/32")
```

### VPN Interface Names

| VPN Type | Common Interface |
|----------|------------------|
| OpenVPN  | `tun0` or `tap0` |
| WireGuard | `wg0` |
| IPsec/IKEv2 | `ipsec0` |
| PPTP | `ppp0` |
| Cisco AnyConnect | `tun0` |

## 🎯 Usage

### Automatic Mode

Once installed in `/etc/NetworkManager/dispatcher.d/`, the script automatically runs when:
- Network connection is established
- VPN connection starts/stops
- Network interface changes

### Manual Commands

```bash
# Add split tunnel routes
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel add

# Remove split tunnel routes
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel remove

# Check current status
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel status

# Test configuration (dry run)
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel test

# Show help
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel help
```

### Using Setup Script

```bash
# Interactive menu
sudo ./setup.sh

# Show status
sudo ./setup.sh status

# Uninstall
sudo ./setup.sh uninstall
```

## 🔧 How It Works

1. **Route Detection**: Script identifies the default gateway that's NOT the VPN interface
2. **Route Addition**: Creates specific routes for configured subnets through the physical gateway
3. **Priority Handling**: These routes take precedence over the VPN's default route
4. **Automatic Updates**: NetworkManager dispatcher ensures routes persist across network changes

### Network Flow

```
┌─────────────────┐
│   Your Device   │
└────────┬────────┘
         │
    ┌────▼─────┐
    │ Decision │
    └────┬─────┘
         │
    ┌────▼──────────────────┐
    │ Is destination in     │
    │ BYPASS_SUBNETS?       │
    └────┬────────────┬─────┘
         │            │
     Yes │            │ No
         │            │
    ┌────▼────┐  ┌───▼─────┐
    │ Local   │  │   VPN   │
    │ Gateway │  │ Tunnel  │
    └─────────┘  └─────────┘
```

## 🧐 Verification

### Check Active Routes

```bash
# View all routes
ip route show

# Check specific subnet
ip route show 192.168.1.0/24

# View routing table
ip route list table main
```

### Expected Output

```bash
default via 10.8.0.1 dev tun0 proto static metric 50
192.168.1.0/24 via 192.168.0.1 dev eth0              # ← Bypass route
192.168.2.0/24 via 192.168.0.1 dev eth0              # ← Bypass route
10.8.0.0/24 dev tun0 proto kernel scope link
```

### Check Logs

```bash
# View recent log entries
tail -f /var/log/split_tunnel.log

# View all logs
cat /var/log/split_tunnel.log

# Filter errors only
grep ERROR /var/log/split_tunnel.log
```

## 🛑 Troubleshooting

### Routes Not Applied

**Symptom**: Routes don't appear when running `ip route show`

**Solutions**:
```bash
# Check if NetworkManager is running
systemctl status NetworkManager

# Verify script permissions
ls -l /etc/NetworkManager/dispatcher.d/99-split-tunnel

# Check for errors in logs
tail -20 /var/log/split_tunnel.log

# Run manually with verbose output
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel add
```

### VPN Interface Not Found

**Symptom**: "No non-VPN default route or interface found"

**Solutions**:
```bash
# List all network interfaces
ip link show

# Check VPN interface name
ip addr show | grep tun

# Update VPN_INTERFACE in config
sudo nano /etc/split_tunnel/split_tunnel.conf
```

### Routes Disappear After VPN Reconnect

**Symptom**: Routes work initially but vanish after VPN disconnect/reconnect

**Solution**: The script should handle this automatically. If not:
```bash
# Check dispatcher script is in correct location
ls -l /etc/NetworkManager/dispatcher.d/99-split-tunnel

# Manually trigger
sudo systemctl restart NetworkManager
```

### Permission Denied

**Symptom**: "Permission denied" or "Operation not permitted"

**Solutions**:
```bash
# Ensure running as root
sudo -i

# Check script permissions
sudo chmod +x /etc/NetworkManager/dispatcher.d/99-split-tunnel

# Verify you have sudo access
sudo -v
```

### Lock File Issues

**Symptom**: "Another instance is running" message

**Solutions**:
```bash
# Remove stale lock file
sudo rm -f /var/run/split_tunnel.lock

# Check for hung processes
ps aux | grep split_tunnel
```

## ❓ FAQ

### Q: Will this work with my VPN client?
**A:** Yes! This works with any VPN that creates a network interface (OpenVPN, WireGuard, IPsec, etc.). Just configure the correct interface name.

### Q: Can I use this with multiple VPNs simultaneously?
**A:** Yes, but you'll need to specify which VPN interface to exclude. The script excludes one VPN interface at a time.

### Q: Does this affect VPN security?
**A:** Traffic to bypass subnets goes through your regular internet connection, not the VPN. Only configure trusted local networks.

### Q: Can I add/remove subnets without reinstalling?
**A:** Yes! Edit `/etc/split_tunnel/split_tunnel.conf` and run `sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel add`.

### Q: How do I temporarily disable split tunneling?
**A:** Run `sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel remove` to remove routes. They'll be re-added on next network change.

### Q: Does this work on Wi-Fi and Ethernet?
**A:** Yes, it automatically detects the active interface and adjusts routes accordingly.

### Q: Can I use wildcards in subnet definitions?
**A:** Use CIDR notation ranges instead. For example, `10.0.0.0/8` covers all 10.x.x.x addresses.

## 🤝 Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

### Development

```bash
# Fork the repository
git clone https://github.com/ChiefGyk3D/split_tunnel_switch.git

# Create a feature branch
git checkout -b feature/your-feature-name

# Make changes and test
sudo ./split_tunnel.sh test

# Commit and push
git commit -am "Add your feature"
git push origin feature/your-feature-name
```

## 📜 License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- NetworkManager dispatcher system
- Linux routing and networking stack
- All contributors and users of this project

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/ChiefGyk3D/split_tunnel_switch/issues)
- **Discussions**: [GitHub Discussions](https://github.com/ChiefGyk3D/split_tunnel_switch/discussions)

---

**Made with ❤️ for the Linux community**
