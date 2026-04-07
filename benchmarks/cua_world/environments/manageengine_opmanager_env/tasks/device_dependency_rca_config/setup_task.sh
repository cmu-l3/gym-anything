#!/bin/bash
# setup_task.sh — Device Dependency Map Configuration for Root Cause Analysis
# Prepares the environment by cleaning up conflicting devices and writing the spec document.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Device Dependency RCA Config Task ==="

# ------------------------------------------------------------
# 1. Wait for OpManager to be ready
# ------------------------------------------------------------
echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=180
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "[setup] WARNING: OpManager not ready after ${WAIT_TIMEOUT}s, continuing anyway." >&2
        break
    fi
done
echo "[setup] OpManager is ready."

# ------------------------------------------------------------
# 2. Delete any existing devices that conflict with our IP range (best effort)
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi

echo "[setup] Cleaning up any conflicting devices..."
if [ -n "$API_KEY" ]; then
    DEVICES_JSON=$(curl -sf "http://localhost:8060/api/json/device/listDevices?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$DEVICES_JSON" ]; then
        python3 -c "
import json, sys, subprocess
try:
    data = json.loads(sys.argv[1])
    devices = data if isinstance(data, list) else data.get('data', data.get('devices', data.get('deviceList', [])))
    if isinstance(devices, dict):
        devices = devices.get('data', [])
    for d in devices:
        if not isinstance(d, dict): continue
        ip = str(d.get('ipAddress', d.get('ip', d.get('deviceIP', ''))))
        name = str(d.get('displayName', d.get('name', '')))
        if ip.startswith('10.0.1.') or 'Campus' in name or 'Distro' in name or 'Access' in name:
            dev_id = d.get('monitorId', d.get('id', d.get('name', '')))
            if dev_id:
                print(f'Deleting {name} ({ip})...')
                subprocess.run(['curl', '-sf', '-X', 'POST', f'http://localhost:8060/api/json/device/deleteDevice?apiKey={sys.argv[2]}&deviceName={dev_id}'], capture_output=True)
except Exception as e:
    pass
" "$DEVICES_JSON" "$API_KEY"
    fi
fi

# ------------------------------------------------------------
# 3. Write network topology spec to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/network_dependency_spec.txt" << 'SPEC_EOF'
CAMPUS NETWORK TOPOLOGY SPECIFICATION
==================================================
Date: 2024-04-12
Author: Lead Network Architect
Subject: OpManager Device Addition & RCA Dependency Configuration

INSTRUCTIONS:
The new campus hierarchy is being deployed. To prevent alert storms
when upstream devices fail, you MUST add these devices to OpManager
and explicitly configure their parent-child dependencies.

(Note: These devices will show as 'down' because they are not yet reachable
on the lab network. This is expected. Just add them and configure dependencies).

DEVICE INVENTORY & TOPOLOGY
--------------------------------------------------
1. ROOT DEVICE (Core)
   Name: Campus-Core-RTR-01
   IP Address: 10.0.1.1
   Category: Router
   Parent Device: [None - This is the root]

2. DISTRIBUTION TIER
   Name: Distro-Switch-A
   IP Address: 10.0.1.2
   Category: Switch
   Parent Device: Campus-Core-RTR-01

   Name: Distro-Switch-B
   IP Address: 10.0.1.3
   Category: Switch
   Parent Device: Campus-Core-RTR-01

3. ACCESS TIER
   Name: Access-Switch-Floor2
   IP Address: 10.0.1.4
   Category: Switch
   Parent Device: Distro-Switch-A

IMPLEMENTATION DETAILS:
1. Add all four devices to the inventory (Settings > Discovery > Add Device, or Inventory > Add Device).
2. For each child device, go to its Snapshot / settings page and locate the "Dependency" or "Dependent On" configuration.
3. Select the specified Parent Device for each child.
4. Save the configuration.

==================================================
END OF DOCUMENT
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/network_dependency_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Topology specification written to $DESKTOP_DIR/network_dependency_spec.txt"

# ------------------------------------------------------------
# 4. Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/device_dependency_task_start.txt
date +%s > /tmp/task_start_time.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 5. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# Take an initial screenshot
take_screenshot "/tmp/device_dependency_setup_screenshot.png" || true

echo "[setup] === Device Dependency RCA Config Task Setup Complete ==="