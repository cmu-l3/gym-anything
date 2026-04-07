#!/bin/bash
echo "=== Setting up redundant_sensor_drift_calibration task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready and populated
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/redundant_sensor_drift_calibration_result.json 2>/dev/null || true
rm -f /tmp/redundant_sensor_drift_calibration_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name to ensure a clean slate
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Sensor Calibration'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Sensor Calibration' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify required metrics exist
echo "Checking for required IoT sensor metrics..."
for metric in "servers.web_traffic.speed_sensor_1" \
              "servers.web_traffic.speed_sensor_2"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Record task start timestamp (for detecting newly created files)
date +%s > /tmp/redundant_sensor_drift_calibration_start_ts

# Navigate Firefox to the Graphite Dashboard page
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/redundant_sensor_drift_calibration_start_screenshot.png

echo "=== redundant_sensor_drift_calibration setup complete ==="