#!/bin/bash
# setup_task.sh — Maintenance Downtime Scheduling
# Writes the maintenance schedule document to the desktop, waits for OpManager, and sets up the initial state.

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
# Write Maintenance Schedule Spec file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/maintenance_schedule.txt" << 'SPEC_EOF'
IT INFRASTRUCTURE MAINTENANCE SCHEDULE
Document Version: 1.1
Approved By: Change Advisory Board (CAB)

The following maintenance windows have been approved and must be configured
in the monitoring system (OpManager) to suppress false alerts during planned work.
Navigate to the Downtime Scheduler configuration and add all three schedules.

SCHEDULE 1: Core Network Updates
---------------------------------
Name: Core-Network-Weekend-Maintenance
Description: Weekly maintenance window for core network infrastructure firmware and configuration updates
Schedule Type: Recurring -> Weekly
Days: Saturday
Time: 02:00 AM to 06:00 AM

SCHEDULE 2: DB Cluster Patching
---------------------------------
Name: Database-Cluster-Patch-Window
Description: Monthly patching and reboot window for production database cluster nodes
Schedule Type: Recurring -> Monthly
Days: 1st Sunday (or Day 1 of the month)
Time: 12:00 AM (midnight) to 04:00 AM

SCHEDULE 3: Annual DR Testing
---------------------------------
Name: DR-Failover-Exercise-2025
Description: One-time disaster recovery failover test for all data center infrastructure
Schedule Type: One-time
Date: December 15, 2025
Time: 10:00 PM (Dec 15) to 04:00 AM (Dec 16)

Note: If asked to associate devices with the downtime, select "All Devices" or the local server (localhost / 127.0.0.1).
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/maintenance_schedule.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Maintenance schedule document written to $DESKTOP_DIR/maintenance_schedule.txt"

# ------------------------------------------------------------
# Remove any pre-existing downtime schedules with the spec names
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi

# Try a few common downtime scheduler endpoints to clear existing entries
if [ -n "$API_KEY" ]; then
    DT_JSON=$(curl -sf "http://localhost:8060/api/json/admin/getDowntimeSchedulers?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$DT_JSON" ]; then
        python3 -c "
import json, sys, subprocess
try:
    data = json.loads(sys.argv[1])
    dts = data if isinstance(data, list) else data.get('data', data.get('downtimeSchedules', []))
    for dt in dts:
        if isinstance(dt, dict):
            name = dt.get('taskName', dt.get('name', dt.get('scheduleName', '')))
            if name in ['Core-Network-Weekend-Maintenance', 'Database-Cluster-Patch-Window', 'DR-Failover-Exercise-2025']:
                taskId = dt.get('taskId', dt.get('id', ''))
                if taskId:
                    subprocess.run(['curl', '-sf', '-X', 'POST', f'http://localhost:8060/api/json/admin/deleteDowntimeScheduler?apiKey={sys.argv[2]}&taskId={taskId}'])
except Exception:
    pass
" "$DT_JSON" "$API_KEY" 2>/dev/null || true
    fi
fi

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/maintenance_task_start.txt
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start time recorded: $(cat /tmp/maintenance_task_start.txt)"

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# ------------------------------------------------------------
# Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/maintenance_downtime_setup_screenshot.png" || true

echo "[setup] === Maintenance Downtime Scheduling Setup Complete ==="