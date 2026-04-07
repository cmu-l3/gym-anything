#!/bin/bash
# setup_task.sh — Datacenter Device Onboarding
# Prepares the environment by waiting for OpManager, ensuring a clean slate,
# and placing the rack manifest on the desktop.

source /workspace/scripts/task_utils.sh

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
# 1. Clean up any pre-existing devices with matching names/IPs
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi

echo "[setup] Attempting to remove any existing target devices..."
DEVICE_JSON=$(curl -sf "http://localhost:8060/api/json/device/listDevices?apiKey=${API_KEY}" 2>/dev/null || true)
if [ -n "$DEVICE_JSON" ]; then
    # Look for our target IPs and attempt deletion
    for target_ip in "10.200.1.1" "10.200.1.2" "10.200.2.1" "10.200.3.10" "10.200.4.1"; do
        DEV_NAME=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    devices = data if isinstance(data, list) else data.get('data', data.get('devices', []))
    for d in devices:
        if isinstance(d, dict) and d.get('ipAddress', d.get('ip', '')) == sys.argv[2]:
            print(d.get('deviceName', d.get('name', '')))
            break
except Exception:
    pass
" "$DEVICE_JSON" "$target_ip" 2>/dev/null || true)

        if [ -n "$DEV_NAME" ]; then
            curl -sf -X POST \
                "http://localhost:8060/api/json/device/deleteDevice?apiKey=${API_KEY}&deviceName=${DEV_NAME}" \
                -o /dev/null 2>/dev/null || true
            echo "[setup] Deleted existing device '${DEV_NAME}' at IP ${target_ip}."
        fi
    done
fi

# ------------------------------------------------------------
# 2. Write Rack Manifest to Desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"
MANIFEST_FILE="$DESKTOP_DIR/dc2_rack_manifest.txt"

cat > "$MANIFEST_FILE" << 'EOF'
===========================================================
   DC2 RACK MANIFEST — Post-Expansion Device Inventory
   Prepared by: Data Center Operations
   Date: 2024-11-15
   Revision: 1.0
===========================================================

INSTRUCTIONS FOR NETWORK MONITORING TEAM:
  All devices below have been physically installed, cabled,
  and assigned IP addresses. Each must be registered in
  ManageEngine OpManager with the EXACT display name and
  IP address shown below. Devices may initially appear as
  unreachable — this is expected until SNMP is configured
  on each device during Phase 2.

-----------------------------------------------------------
RACK A1 — Network Core (Row A, Cabinet 1)
-----------------------------------------------------------
  Device Name:    DC2-Core-Switch-01
  IP Address:     10.200.1.1
  Role:           Primary L3 core switch
  Hardware:       Cisco Nexus 9300
  Rack Unit:      U40-U42

  Device Name:    DC2-Core-Switch-02
  IP Address:     10.200.1.2
  Role:           Redundant L3 core switch
  Hardware:       Cisco Nexus 9300
  Rack Unit:      U37-U39

-----------------------------------------------------------
RACK A2 — Security / Distribution (Row A, Cabinet 2)
-----------------------------------------------------------
  Device Name:    DC2-Distribution-FW
  IP Address:     10.200.2.1
  Role:           Inter-VLAN firewall / distribution
  Hardware:       Palo Alto PA-5260
  Rack Unit:      U38-U42

-----------------------------------------------------------
RACK B3 — Storage (Row B, Cabinet 3)
-----------------------------------------------------------
  Device Name:    DC2-Storage-Array-01
  IP Address:     10.200.3.10
  Role:           Primary SAN storage array
  Hardware:       NetApp AFF A400
  Rack Unit:      U20-U28

-----------------------------------------------------------
RACK C1 — Compute (Row C, Cabinet 1)
-----------------------------------------------------------
  Device Name:    DC2-Hypervisor-Node-01
  IP Address:     10.200.4.1
  Role:           VMware ESXi hypervisor host
  Hardware:       Dell PowerEdge R750
  Rack Unit:      U1-U2

===========================================================
END OF MANIFEST — 5 devices total
===========================================================
EOF

chown ga:ga "$MANIFEST_FILE" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Rack manifest written to $MANIFEST_FILE"

# ------------------------------------------------------------
# 3. Record task start timestamp and baseline
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/dc2_onboarding_task_start.txt
date +%s > /tmp/task_start_time.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 4. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager 3 || true

# Take an initial screenshot
take_screenshot "/tmp/dc2_onboarding_setup_screenshot.png" || true

echo "[setup] === Datacenter Device Onboarding Task Setup Complete ==="