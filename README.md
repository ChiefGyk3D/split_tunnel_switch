# NetworkManager Split Tunneling Script

This script enables split tunneling by allowing specified subnets to bypass a VPN connection. It is designed to be used with **NetworkManager** and should be placed in `/etc/NetworkManager/dispatcher.d/99-split-tunnel` for automatic execution when network changes occur.

However, you can also optionally run this script manually if you don't want to do it automatically.
## 📌 Features
- Automatically detects the active network interface and default gateway.
- Routes specific subnets outside of the VPN.
- Ensures the split tunnel rules persist after network changes.

## 🛠️ Installation

### 1. Copy the Script to the Correct Location
Move the script to the NetworkManager dispatcher directory and make it executable:

```bash
sudo mv split_tunnel.sh /etc/NetworkManager/dispatcher.d/split_tunnel
sudo chmod +x /etc/NetworkManager/dispatcher.d/split_tunnel
```

### 2. Edit the Script (Optional)
Modify the `BYPASS_SUBNETS` array in the script to include the subnets you want to bypass the VPN.
```bash
BYPASS_SUBNETS=("192.168.1.0/24" "192.168.2.0/24")
```

### 3. Restart NetworkManager
```bash
sudo systemctl restart NetworkManager
```

## 🚀 Usage
Once installed, the script will automatically run whenever a network change is detected, ensuring the specified subnets bypass the VPN.

To manually execute the script:
```bash
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel
```

## 🧐 Verification
Check if the routes have been added:
```bash
ip route show
```
You should see entries similar to:

```bash
192.168.x.0/24 via 192.168.x.x dev eth0
192.168.y.0/24 via 192.168.y.x dev eth0
```

## 🛑 Troubleshooting
- **No default route or network interface found!**
  - Ensure your system has an active internet connection.
  - Run `ip route show` to verify network configuration.

- **Route not added properly**
  - Run the script manually:  
    ```bash
    sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel
    ```
  - Check logs using:
    ```bash
    journalctl -u NetworkManager --no-pager | grep "dispatcher"
    ```

## 📜 License
This project is licensed under the GPL v3 License.
