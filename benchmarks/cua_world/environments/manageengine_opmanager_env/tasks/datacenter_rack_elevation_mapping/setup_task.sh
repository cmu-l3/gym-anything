#!/bin/bash
# setup_task.sh — Datacenter Rack Elevation Mapping
# Prepares the OS network interfaces, writes the manifest, and waits for OpManager.

source /workspace/scripts/task_utils.sh

echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=120
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "[setup] ERROR: OpManager not ready after ${WAIT_TIMEOUT}s" >&2
        exit 1
    fi
done
echo "[setup] OpManager is ready."

# ------------------------------------------------------------
# 1. Bind additional IP addresses for discovery
# ------------------------------------------------------------
echo "[setup] Binding alias IP addresses for 127.0.0.2 and 127.0.0.3..."
ip addr add 127.0.0.2/32 dev lo 2>/dev/null || true
ip addr add 127.0.0.3/32 dev lo 2>/dev/null || true

# Restart SNMPd so it actively listens on the newly brought up aliases if needed
systemctl restart snmpd 2>/dev/null || true
sleep 2

# Verify they are responding
ping -c 1 127.0.0.2 > /dev/null || echo "[setup] Warning: 127.0.0.2 ping failed"
ping -c 1 127.0.0.3 > /dev/null || echo "[setup] Warning: 127.0.0.3 ping failed"

# ------------------------------------------------------------
# 2. Write the deployment manifest to the Desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/rack_deployment_manifest.csv" << 'CSV_EOF'
Device IP,Hostname,Device Type,Rack Name,U-Slot,Size
127.0.0.1,Core-Router-Local,Router,Core-Rack-A1,40,2U
127.0.0.2,Switch-Agg-01,Switch,Core-Rack-A1,35,1U
127.0.0.3,Switch-Agg-02,Switch,Core-Rack-A1,34,1U
CSV_EOF

chown ga:ga "$DESKTOP_DIR/rack_deployment_manifest.csv" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Deployment manifest written to $DESKTOP_DIR/rack_deployment_manifest.csv"

# ------------------------------------------------------------
# 3. Clean up any pre-existing racks with this name (best-effort)
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi
# We skip API deletion of racks here as the UI is the primary way to interact with Rack Views,
# and it shouldn't exist in a fresh install anyway.

# ------------------------------------------------------------
# 4. Record task start timestamp and setup UI
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/rack_mapping_task_start.txt
echo "[setup] Task start time recorded."

ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/rack_mapping_setup_screenshot.png" || true

echo "[setup] datacenter_rack_elevation_mapping setup complete."