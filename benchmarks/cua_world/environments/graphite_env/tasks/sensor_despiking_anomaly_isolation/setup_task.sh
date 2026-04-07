#!/bin/bash
echo "=== Setting up sensor_despiking_anomaly_isolation task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/sensor_despiking_anomaly_isolation_result.json 2>/dev/null || true
rm -f /tmp/sensor_despiking_anomaly_isolation_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name (ensure clean initial state)
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Sensor Quality Analysis'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Sensor Quality Analysis' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify required metric exists
echo "Checking for required metric..."
if metric_exists "servers.web_traffic.speed_sensor_1"; then
    echo "  Found: servers.web_traffic.speed_sensor_1"
else
    echo "  WARNING: Missing: servers.web_traffic.speed_sensor_1"
fi

# Record task start timestamp
date +%s > /tmp/sensor_despiking_anomaly_isolation_start_ts

# Navigate Firefox to the Graphite Dashboard page
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/sensor_despiking_anomaly_isolation_start_screenshot.png

echo "=== sensor_despiking_anomaly_isolation setup complete ==="