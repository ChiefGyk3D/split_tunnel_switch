#!/bin/bash
#for auto switching place in /etc/NetworkManager/dispatcher.d/99-split-tunnel

# Define the subnets that should bypass ProtonVPN
BYPASS_SUBNETS=("192.168.1.0/24" "192.168.2.0/24")

# Find the active network interface and gateway
DEFAULT_ROUTE=$(ip route show default | awk '/default/ {print $3}')
DEFAULT_INTERFACE=$(ip route show default | awk '/default/ {print $5}')

# Ensure we have a valid route and interface
if [ -z "$DEFAULT_ROUTE" ] || [ -z "$DEFAULT_INTERFACE" ]; then
    echo "Error: No default route or network interface found!"
    exit 1
fi

echo "Using interface: $DEFAULT_INTERFACE with gateway: $DEFAULT_ROUTE"

# Loop through each subnet and add a route
for SUBNET in "${BYPASS_SUBNETS[@]}"; do
    echo "Adding route for $SUBNET via $DEFAULT_INTERFACE ($DEFAULT_ROUTE)..."
    sudo ip route add "$SUBNET" via "$DEFAULT_ROUTE" dev "$DEFAULT_INTERFACE"

    # Verify if the route was successfully added
    if ip route show | grep -q "$SUBNET"; then
        echo "Successfully added: $SUBNET -> $DEFAULT_INTERFACE ($DEFAULT_ROUTE)"
    else
        echo "Failed to add route for: $SUBNET"
    fi
done

echo "Split tunneling for local subnets is now active."

