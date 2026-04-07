#!/bin/bash
# setup_task.sh — Custom Operations Dashboard Configuration
# Waits for OpManager to be ready, writes a spec document, records start time, and opens Firefox.

source /workspace/scripts/task_utils.sh

echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=180
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "[setup] WARNING: OpManager not ready after ${WAIT_TIMEOUT}s. Continuing..." >&2
        break
    fi
done
echo "[setup] OpManager is ready."

# ------------------------------------------------------------
# 1. Clean up any existing dashboards with the target names (best-effort)
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi

for db_name in "NOC-Live-Operations" "Capacity-Planning-View" "Executive-KPI-Board"; do
    DB_JSON=$(curl -sf "http://localhost:8060/api/json/dashboard/getDashboards?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$DB_JSON" ]; then
        DB_ID=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    dashboards = data if isinstance(data, list) else data.get('data', data.get('dashboards', []))
    for d in dashboards:
        if isinstance(d, dict) and d.get('dashboardName', d.get('name', '')) == sys.argv[2]:
            print(d.get('dashboardId', d.get('id', '')))
            break
except Exception:
    pass
" "$DB_JSON" "$db_name" 2>/dev/null || true)
        
        if [ -n "$DB_ID" ]; then
            curl -sf -X POST \
                "http://localhost:8060/api/json/dashboard/deleteDashboard?apiKey=${API_KEY}&dashboardId=${DB_ID}" \
                -o /dev/null 2>/dev/null || true
            echo "[setup] Deleted pre-existing dashboard '${db_name}' (id=${DB_ID})."
        fi
    fi
done

# ------------------------------------------------------------
# 2. Write requirements file to Desktop for realistic context
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/dashboard_requirements.txt" << 'SPEC_EOF'
IT Operations Dashboard Requirements
Date: 2024-03-15
Requested By: IT Director

Please create the following three dashboard tabs in OpManager. Each dashboard
must contain at least one relevant widget to be considered complete.

Dashboard 1:
- Name: NOC-Live-Operations
- Purpose: Active monitoring and fault detection
- Suggested Widgets: Alarm Summary, Device Status

Dashboard 2:
- Name: Capacity-Planning-View
- Purpose: Resource utilization and forecasting
- Suggested Widgets: Top N Devices by CPU/Memory/Disk

Dashboard 3:
- Name: Executive-KPI-Board
- Purpose: High-level availability and infrastructure health
- Suggested Widgets: Overall Availability, Infrastructure Summary

Note: The exact names listed above must be used for the dashboard tabs.
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/dashboard_requirements.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Requirements document written to $DESKTOP_DIR/dashboard_requirements.txt"

# ------------------------------------------------------------
# 3. Record initial state and task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/dashboard_task_start.txt
date +%s > /tmp/task_start_timestamp

# ------------------------------------------------------------
# 4. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/dashboard_setup_screenshot.png" || true

echo "[setup] custom_operations_dashboard_config setup complete."