#!/bin/bash
# setup_task.sh — WAN Polling Optimization and Overrides
# Waits for OpManager, creates the policy document, and records the initial state.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up WAN Polling Optimization Task ==="

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
# 2. Write the tuning policy file to the desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/polling_tuning_policy.txt" << 'POLICY_EOF'
WAN Polling Optimization and Local Overrides Policy
Document ID: NET-POL-109
Effective Date: 2024-05-01

1. GLOBAL POLLING SETTINGS
We are experiencing false positive alerts from high-latency satellite links. Update the global system polling settings to be more tolerant:
- Ping Timeout: 5000 milliseconds (or 5 seconds)
- Ping Retries: 4
- Default Availability Polling Interval: 15 minutes
(Location: Settings > Basic Settings > System Settings, or Settings > Performance > Polling Engine)

2. LOCAL DATACENTER OVERRIDES
Critical local core switches must be polled aggressively. Override the default polling interval for the following two devices to EXACTLY 1 minute:
- Local-Core-SW-01 (IP: 10.0.1.11)
- Local-Core-SW-02 (IP: 10.0.1.12)

Note: If these devices do not exist in the inventory, add them first (Settings > Discovery > Add Device). Use SNMP v2c (Community: public) or add them without SNMP. Ensure their specific polling interval is set to 1 minute.
POLICY_EOF

chown ga:ga "$DESKTOP_DIR/polling_tuning_policy.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Polling tuning policy written to $DESKTOP_DIR/polling_tuning_policy.txt"

# ------------------------------------------------------------
# 3. Add the devices via API (Best Effort - to save agent time)
# If this fails, the agent will add them per the instructions
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi
if [ -n "$API_KEY" ]; then
    echo "[setup] Attempting to pre-provision devices..."
    opmanager_api_post "/api/json/device/addDevice" "deviceName=Local-Core-SW-01&ipAddress=10.0.1.11&type=Switch&community=public" 2>/dev/null || true
    opmanager_api_post "/api/json/device/addDevice" "deviceName=Local-Core-SW-02&ipAddress=10.0.1.12&type=Switch&community=public" 2>/dev/null || true
fi

# ------------------------------------------------------------
# 4. Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/wan_polling_task_start.txt
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 5. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# ------------------------------------------------------------
# 6. Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/wan_polling_setup_screenshot.png" || true

echo "[setup] === WAN Polling Optimization Task Setup Complete ==="