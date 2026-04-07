#!/bin/bash
# setup_task.sh — NOC Shift Alarm Triage and Acknowledgment
# Creates 5 failing URL monitors to generate active alarms,
# and writes the shift handover instructions to the desktop.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up NOC Shift Alarm Triage Task ==="

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
# 2. Get API Key
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi
if [ -z "$API_KEY" ]; then
    LOGIN_RESP=$(curl -sf -X POST \
        "http://localhost:8060/apiv2/login" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin&password=Admin%40123" 2>/dev/null || true)
    if [ -n "$LOGIN_RESP" ]; then
        API_KEY=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    print(d.get('apiKey', d.get('data', {}).get('apiKey', '')))
except Exception:
    pass
" "$LOGIN_RESP" 2>/dev/null || true)
    fi
fi

# ------------------------------------------------------------
# 3. Create failing monitors to generate alarms
# ------------------------------------------------------------
# We use TEST-NET-1 (192.0.2.x) which is guaranteed to drop packets,
# causing an immediate timeout and triggering an alarm in OpManager.
echo "[setup] Creating URL monitors to generate alarms..."

DEVICES=("Core-Switch-01" "DB-Node-01" "SAN-Storage-01" "Edge-Router-VPN" "Web-Proxy-01")
IP_SUFFIX=101

for dev in "${DEVICES[@]}"; do
    # Delete if exists
    MON_JSON=$(curl -sf "http://localhost:8060/api/json/url/getURLMonitorList?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$MON_JSON" ]; then
        MON_ID=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    mons = d if isinstance(d, list) else d.get('data', d.get('monitors', []))
    for m in mons:
        if isinstance(m, dict) and m.get('displayName','') == sys.argv[2]:
            print(m.get('monitorId', m.get('id', '')))
            break
except Exception:
    pass
" "$MON_JSON" "$dev" 2>/dev/null || true)
        if [ -n "$MON_ID" ]; then
            curl -sf -X POST "http://localhost:8060/api/json/url/deleteURLMonitor?apiKey=${API_KEY}&monitorId=${MON_ID}" -o /dev/null 2>/dev/null || true
        fi
    fi

    # Create monitor with 1 minute interval and 1 second timeout
    opmanager_api_post "/api/json/url/addURLMonitor" \
        "displayName=${dev}&url=http%3A%2F%2F192.0.2.${IP_SUFFIX}&pollInterval=1&timeout=1" \
        2>/dev/null || true
    echo "[setup] Created monitor for $dev"
    IP_SUFFIX=$((IP_SUFFIX + 1))
done

# ------------------------------------------------------------
# 4. Wait for alarms to trigger
# ------------------------------------------------------------
echo "[setup] Waiting 75 seconds for OpManager to poll monitors and generate alarms..."
sleep 75

# ------------------------------------------------------------
# 5. Write shift handover document
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/morning_shift_triage.txt" << 'DOC_EOF'
NOC SHIFT HANDOVER: MORNING
Date: 2024-11-15
Shift Lead: J. Doe

ALARM TRIAGE INSTRUCTIONS:
Please log into OpManager and review the active alarms. Apply the following actions:

1. PLANNED MAINTENANCE (ACKNOWLEDGE)
The following devices are undergoing emergency patching. Acknowledge their active alarms and add the exact note "Maintenance CHG-90210" to each:
- Core-Switch-01
- DB-Node-01
- SAN-Storage-01

2. FALSE POSITIVES (CLEAR)
The following devices triggered temporary reachability alerts during the 03:00 AM backup window. The issues are resolved. Please clear these alarms completely:
- Edge-Router-VPN
- Web-Proxy-01

NOTE: Do not modify any other alarms that may be present on the dashboard.
If cleared alarms immediately re-trigger during your shift, ignore them—your clear action is already logged.
DOC_EOF

chown ga:ga "$DESKTOP_DIR/morning_shift_triage.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Shift handover document written to $DESKTOP_DIR/morning_shift_triage.txt"

# ------------------------------------------------------------
# 6. Record task start timestamp
# ------------------------------------------------------------
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 7. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/task_initial.png" || true

echo "[setup] === Task Setup Complete ==="