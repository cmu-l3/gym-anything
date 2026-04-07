#!/bin/bash
# setup_task.sh — Broadcast AoIP Template Config
echo "=== Setting up Broadcast AoIP Template Config Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

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
# Ensure 127.0.0.1 is in the inventory so the agent can modify it.
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi
if [ -n "$API_KEY" ]; then
    RESP=$(curl -sf "http://localhost:8060/api/json/device/getDeviceDetails?apiKey=${API_KEY}&ipAddress=127.0.0.1" 2>/dev/null || true)
    if ! echo "$RESP" | grep -q "127.0.0.1"; then
        echo "[setup] Adding 127.0.0.1 to inventory..."
        curl -sf -X POST "http://localhost:8060/api/json/device/addDevice" \
             -d "apiKey=${API_KEY}&ipAddress=127.0.0.1&displayName=localhost&community=public" 2>/dev/null || true
        sleep 5
    fi
fi

# ------------------------------------------------------------
# Write hardware onboarding spec file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/hardware_onboarding_spec.txt" << 'SPEC_EOF'
Hardware Onboarding Specification
Document ID: HW-ONB-001

EQUIPMENT DETAILS
-----------------
Vendor: Lawo
Model: mc² Micro Core
Device Category: Switch
System OID (SysOID): .1.3.6.1.4.1.50536.10.1

ACTION REQUIRED
---------------
1. Create a new Device Template in OpManager named exactly: Lawo-AoIP-Core
   - Assign the Vendor, Category, and SysOID listed above.

2. Locate the existing active core currently monitored at IP: 127.0.0.1
   - Change its Display Name to: Studio-A-Core
   - Change its Device Template to: Lawo-AoIP-Core
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/hardware_onboarding_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Spec file written to $DESKTOP_DIR/hardware_onboarding_spec.txt"

# ------------------------------------------------------------
# Record task start timestamp and open Firefox
# ------------------------------------------------------------
date +%s > /tmp/task_start_time.txt

if type ensure_firefox_on_opmanager >/dev/null 2>&1; then
    ensure_firefox_on_opmanager || true
else
    su - ga -c "DISPLAY=:1 firefox http://localhost:8060 &" 2>/dev/null || true
    sleep 5
    DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take an initial screenshot
if type take_screenshot >/dev/null 2>&1; then
    take_screenshot "/tmp/aoip_setup_screenshot.png" ga || true
else
    DISPLAY=:1 scrot "/tmp/aoip_setup_screenshot.png" 2>/dev/null || true
fi

echo "[setup] === Setup Complete ==="