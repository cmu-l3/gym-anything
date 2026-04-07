#!/bin/bash
# setup_task.sh — URL Monitor Service Remediation
# Creates two misconfigured URL monitors and writes the service catalog spec to the desktop.


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
# Remove any pre-existing monitors with the spec names (best-effort)
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi

for mon_name in "Internal-Auth-Service" "OpManager-API-Health" "Primary-Web-Portal" "SNMP-Polling-Endpoint" "NOC-Dashboard-Availability"; do
    MON_JSON=$(curl -sf \
        "http://localhost:8060/api/json/url/getURLMonitorList?apiKey=${API_KEY}" \
        2>/dev/null || true)
    if [ -n "$MON_JSON" ]; then
        MON_ID=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    monitors = data if isinstance(data, list) else data.get('data', data.get('monitors', data.get('urlMonitors', [])))
    if not isinstance(monitors, list):
        monitors = []
    for m in monitors:
        if isinstance(m, dict):
            name = m.get('displayName', m.get('name', m.get('monitorName', '')))
            if name == sys.argv[2]:
                print(m.get('monitorId', m.get('id', '')))
                break
except Exception:
    pass
" "$MON_JSON" "$mon_name" 2>/dev/null || true)
        if [ -n "$MON_ID" ]; then
            curl -sf -X POST \
                "http://localhost:8060/api/json/url/deleteURLMonitor?apiKey=${API_KEY}&monitorId=${MON_ID}" \
                -o /dev/null 2>/dev/null || true
            echo "[setup] Deleted pre-existing monitor '${mon_name}' (id=${MON_ID})."
        fi
    fi
done

# ------------------------------------------------------------
# Create the two misconfigured (broken) URL monitors
# ------------------------------------------------------------
echo "[setup] Creating misconfigured URL monitors..."

# Monitor 1: Internal-Auth-Service — wrong URL (points to wrong host:port)
opmanager_api_post "/api/json/url/addURLMonitor" \
    "displayName=Internal-Auth-Service&url=http%3A%2F%2Flocalhost%3A9090%2Fauth&pollInterval=5&timeout=15" \
    2>/dev/null || true
echo "[setup] Created 'Internal-Auth-Service' monitor."

# Monitor 2: OpManager-API-Health — correct URL but poll interval 30 min instead of 3
opmanager_api_post "/api/json/url/addURLMonitor" \
    "displayName=OpManager-API-Health&url=http%3A%2F%2Flocalhost%3A8060%2Fapi%2Fjson%2Fdevice%2FlistDevices&pollInterval=30&timeout=20" \
    2>/dev/null || true
echo "[setup] Created 'OpManager-API-Health' monitor."

# ------------------------------------------------------------
# Write service catalog spec file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/url_service_catalog.txt" << 'CATALOG_EOF'
URL Service Monitoring Catalog
Revision: 4.1
Updated: 2024-02-28

SECTION A: MONITORS REQUIRING CORRECTION
-----------------------------------------
The following monitors are misconfigured and must be fixed:

Monitor: Internal-Auth-Service
  Correct URL: http://localhost:8060/apiclient/ember/Login.jsp
  Correct Poll Interval (minutes): 5
  Correct Timeout (seconds): 15
  Current Problem: Wrong URL configured (currently points to wrong host/port)

Monitor: OpManager-API-Health
  Correct URL: http://localhost:8060/api/json/device/listDevices
  Correct Poll Interval (minutes): 3
  Correct Timeout (seconds): 20
  Current Problem: Poll interval too long (should be 3 minutes, not 30)

SECTION B: NEW MONITORS TO ADD
--------------------------------

New Monitor 1:
  Display Name: Primary-Web-Portal
  URL: http://localhost:8060/client
  Poll Interval (minutes): 5
  Timeout (seconds): 10

New Monitor 2:
  Display Name: SNMP-Polling-Endpoint
  URL: http://localhost:8060
  Poll Interval (minutes): 15
  Timeout (seconds): 30

New Monitor 3:
  Display Name: NOC-Dashboard-Availability
  URL: http://localhost:8060/apiclient/ember
  Poll Interval (minutes): 10
  Timeout (seconds): 15

END OF CATALOG
CATALOG_EOF

chown ga:ga "$DESKTOP_DIR/url_service_catalog.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Service catalog written to $DESKTOP_DIR/url_service_catalog.txt"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/url_monitor_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/url_monitor_setup_screenshot.png" || true

echo "[setup] url_monitor_service_remediation setup complete."
