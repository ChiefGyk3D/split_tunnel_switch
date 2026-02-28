# Quick Start Guide

Get split tunneling working in 5 minutes.

## Prerequisites

- Linux with NetworkManager
- Root/sudo access
- Bash 4.0+

## Step 1: Clone

```bash
git clone https://github.com/ChiefGyk3D/split_tunnel_switch.git
cd split_tunnel_switch
```

## Step 2: Install

**Option A — Interactive (recommended)**:

```bash
sudo bash setup.sh
```

Follow the prompts. The wizard configures subnets, VPN interfaces, and optional features.

**Option B — Quick install (edit config later)**:

```bash
sudo bash setup.sh quick-install
```

## Step 3: Configure (if you used quick-install)

Edit the configuration:

```bash
sudo nano /etc/split_tunnel/split_tunnel.conf
```

At minimum, set your subnets and VPN interface:

```bash
# Tunnel mode: bypass (subnets skip VPN) or include (only subnets use VPN)
TUNNEL_MODE="bypass"

# Subnets to bypass the VPN (IPv4)
BYPASS_SUBNETS=("192.168.1.0/24")

# Subnets to bypass the VPN (IPv6, optional)
BYPASS_SUBNETS_V6=()

# Your VPN interface name(s)
VPN_INTERFACES=("tun0")
```

### Finding Your VPN Interface

```bash
# With VPN connected:
ip link show | grep -E 'tun|wg|tap'

# Common names: tun0 (OpenVPN), wg0 (WireGuard), tailscale0 (Tailscale)
```

### Finding Your Local Subnet

```bash
# Auto-discover
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel discover

# Or check manually
ip -4 addr show | grep 'inet '
```

## Step 4: Validate

```bash
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel validate
```

This checks your config for errors without changing any routes.

## Step 5: Apply

```bash
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel add
```

## Step 6: Verify

```bash
# Check status
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel status

# Check routes
ip route show

# Ping a local device
ping -c 3 192.168.1.1
```

## Optional Features

Enable these in `/etc/split_tunnel/split_tunnel.conf`:

| Feature | Setting | Description |
|---------|---------|-------------|
| Kill switch | `KILL_SWITCH="true"` | Block traffic if VPN drops |
| DNS leak prevention | `DNS_LEAK_PREVENTION="true"` | Route DNS via physical gateway |
| Auto-discover | `AUTO_DISCOVER_SUBNETS="true"` | Auto-detect LAN subnets |
| Connectivity check | `VERIFY_CONNECTIVITY="true"` | Ping hosts after route changes |
| Notifications | `DESKTOP_NOTIFICATIONS="true"` | Desktop alerts |
| Route persistence | (installed by setup.sh) | Re-verify routes every 5 min |

## Common Commands

```bash
SCRIPT="/etc/NetworkManager/dispatcher.d/99-split-tunnel"

sudo $SCRIPT add              # Apply routes
sudo $SCRIPT remove           # Remove everything
sudo $SCRIPT status           # Show current state
sudo $SCRIPT test             # Dry-run
sudo $SCRIPT validate         # Check config
sudo $SCRIPT discover         # Find local subnets
sudo $SCRIPT kill-switch-on   # Enable kill switch
sudo $SCRIPT kill-switch-off  # Disable kill switch
sudo $SCRIPT add -v           # Verbose mode
```

## Uninstall

```bash
sudo bash setup.sh uninstall
```

This removes the dispatcher script, config, log rotation, systemd timer, and firewall rules.

## Next Steps

- Read the full [README.md](README.md) for advanced configuration
- See [CHANGELOG.md](CHANGELOG.md) for version history
- Run `./tests/run_tests.sh` to verify your installation
- See [CONTRIBUTING.md](CONTRIBUTING.md) to help improve the project
