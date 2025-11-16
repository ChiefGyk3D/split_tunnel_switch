# Quick Start Guide

Get up and running with NetworkManager Split Tunneling in 5 minutes!

## 📋 Prerequisites

- Linux system with NetworkManager
- Root/sudo access
- Active VPN connection (or plan to connect)

## 🚀 Installation (Choose One Method)

### Option 1: Interactive Setup (Recommended for First-Time Users)

```bash
sudo ./setup.sh
```

Follow the prompts to:
1. Enter your local subnets (e.g., 192.168.1.0/24)
2. Select your VPN interface (e.g., tun0)
3. Install and test

### Option 2: Quick Install (Fast Setup with Defaults)

```bash
sudo ./setup.sh quick-install
```

Then customize:
```bash
sudo nano /etc/split_tunnel/split_tunnel.conf
```

### Option 3: Manual Installation

```bash
# Install
sudo cp split_tunnel.sh /etc/NetworkManager/dispatcher.d/99-split-tunnel
sudo chmod +x /etc/NetworkManager/dispatcher.d/99-split-tunnel

# Configure
sudo mkdir -p /etc/split_tunnel
sudo cp split_tunnel.conf.example /etc/split_tunnel/split_tunnel.conf
sudo nano /etc/split_tunnel/split_tunnel.conf

# Test
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel test

# Apply
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel add
```

## ✅ Verification

### 1. Check Routes

```bash
ip route show
```

Look for lines like:
```
192.168.1.0/24 via 192.168.0.1 dev eth0
```

### 2. Check Status

```bash
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel status
```

### 3. Test Connectivity

```bash
# Ping a device on your local network
ping 192.168.1.1

# Check if it's using local gateway (not VPN)
traceroute 192.168.1.1
```

## 🎯 Common Configurations

### Home Network

```bash
BYPASS_SUBNETS=("192.168.1.0/24")
VPN_INTERFACE="tun0"
```

### Multiple Networks

```bash
BYPASS_SUBNETS=("192.168.1.0/24" "192.168.2.0/24" "10.0.0.0/24")
VPN_INTERFACE="tun0"
```

### WireGuard VPN

```bash
BYPASS_SUBNETS=("192.168.1.0/24")
VPN_INTERFACE="wg0"
```

### All Private Networks

```bash
BYPASS_SUBNETS=("10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16")
VPN_INTERFACE="tun0"
```

## 🔧 Daily Usage

### Manual Commands

```bash
# Add routes
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel add

# Remove routes
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel remove

# Check status
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel status

# Test configuration
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel test
```

### Automatic Mode

Once installed, routes are automatically managed when:
- You connect/disconnect VPN
- Network interface changes
- NetworkManager detects network events

No manual intervention needed!

## 🛑 Troubleshooting

### Routes Not Working?

```bash
# Check logs
sudo tail -f /var/log/split_tunnel.log

# Verify VPN interface name
ip link show | grep tun

# Test configuration
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel test

# Manually apply
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel add
```

### Can't Access Local Network?

1. Verify subnet is correct:
   ```bash
   ip addr show
   ```

2. Check if route exists:
   ```bash
   ip route show | grep 192.168.1
   ```

3. Test with specific IP:
   ```bash
   ping 192.168.1.1
   traceroute 192.168.1.1
   ```

### VPN Not Working for Internet?

1. Verify VPN is connected:
   ```bash
   ip link show tun0
   ```

2. Check VPN routes:
   ```bash
   ip route show | grep tun0
   ```

3. Make sure split tunnel only affects local subnets, not internet traffic

## 📝 Modify Configuration

Edit the config file:
```bash
sudo nano /etc/split_tunnel/split_tunnel.conf
```

After changes, apply new configuration:
```bash
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel remove
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel add
```

## 🗑️ Uninstall

Using setup script:
```bash
sudo ./setup.sh uninstall
```

Or manually:
```bash
# Remove routes
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel remove

# Remove files
sudo rm /etc/NetworkManager/dispatcher.d/99-split-tunnel
sudo rm -rf /etc/split_tunnel
sudo rm /var/log/split_tunnel.log
```

## 📚 Next Steps

- Read the full [README.md](README.md) for detailed information
- Check [CONTRIBUTING.md](CONTRIBUTING.md) to help improve the project
- Review [FAQ section](README.md#-faq) for common questions

## 💡 Tips

1. **Start with defaults**: Get it working first, then customize
2. **Use test mode**: Always test with `test` command before applying
3. **Check logs**: Logs are your friend when troubleshooting
4. **Backup config**: Keep a copy of your working configuration
5. **Local subnets only**: Only bypass VPN for trusted local networks

## 🆘 Getting Help

- **Documentation**: See [README.md](README.md)
- **Issues**: [GitHub Issues](https://github.com/ChiefGyk3D/split_tunnel_switch/issues)
- **Discussions**: [GitHub Discussions](https://github.com/ChiefGyk3D/split_tunnel_switch/discussions)

---

**Happy split tunneling! 🎉**
