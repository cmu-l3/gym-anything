#!/bin/bash
set -e
echo "=== Setting up recover_deleted_camera task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Refresh auth token
refresh_nx_token > /dev/null 2>&1 || true

# 1. Disable Auto-Discovery to prevent automatic reappearance
# This forces the manual add workflow
echo "Disabling global auto-discovery..."
nx_api_patch "/rest/v1/system/settings" '{"autoDiscoveryEnabled": false}' > /dev/null

# 2. Identify and Delete the 'Server Room Camera'
TARGET_CAM_ID=$(get_camera_id_by_name "Server Room Camera")
SERVER_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo "127.0.0.1")

if [ -n "$TARGET_CAM_ID" ]; then
    echo "Found Server Room Camera (ID: $TARGET_CAM_ID). Deleting..."
    nx_api_delete "/rest/v1/devices/${TARGET_CAM_ID}"
    sleep 2
else
    echo "WARNING: Server Room Camera not found in initial state."
fi

# 3. Create Network Inventory File
# testcamera usually listens on the interface IP.
# We'll provide the Server IP and generic credentials (testcamera accepts any, but agent must follow procedure)
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/network_inventory.txt << EOF
=== CONFIDENTIAL NETWORK INVENTORY ===
Zone: Server Room / Secure Enclave
Last Updated: $(date -I)

MISSING DEVICE REPORT:
Device Name: Server Room Camera
Model: Generic ONVIF / TestCamera
MAC Address: AA:BB:CC:DD:EE:FF
IP Address: ${SERVER_IP}
Port: 80 (ONVIF/HTTP)

CREDENTIALS:
Username: admin
Password: password

INSTRUCTIONS:
- Auto-discovery is DISABLED on this VLAN.
- Use Manual Search to re-provision.
EOF

chmod 644 /home/ga/Documents/network_inventory.txt
chown ga:ga /home/ga/Documents/network_inventory.txt

# 4. Launch Desktop Client
# Kill any existing instances
pkill -f "applauncher" 2>/dev/null || true
pkill -f "client.*networkoptix" 2>/dev/null || true
sleep 2

# Launch Client
APPLAUNCHER=$(find /opt -name "applauncher" -type f 2>/dev/null | head -1)
if [ -n "$APPLAUNCHER" ]; then
    echo "Launching Nx Witness Client..."
    su - ga -c "DISPLAY=:1 $APPLAUNCHER &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Nx Witness"; then
            echo "Client window detected"
            break
        fi
        sleep 1
    done
    
    # Maximize
    DISPLAY=:1 wmctrl -r "Nx Witness" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
    # Note: We rely on the client's auto-login or previous session state. 
    # If it asks for login, the agent has credentials in description/env.
else
    echo "ERROR: Desktop client not found, falling back to Firefox"
    ensure_firefox_running "https://localhost:7001/static/index.html#/settings/cameras"
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="