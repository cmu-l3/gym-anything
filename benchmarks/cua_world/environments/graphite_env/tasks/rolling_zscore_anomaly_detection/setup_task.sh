#!/bin/bash
echo "=== Setting up rolling_zscore_anomaly_detection task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files
rm -f /tmp/rolling_zscore_anomaly_detection_result.json 2>/dev/null || true
rm -f /tmp/rolling_zscore_anomaly_detection_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Statistical Traffic Z-Score'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Statistical Traffic Z-Score' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify required metric exists
echo "Checking required metric..."
if metric_exists "servers.web_traffic.speed_sensor_1"; then
    echo "  Found: servers.web_traffic.speed_sensor_1"
else
    echo "  WARNING: Missing: servers.web_traffic.speed_sensor_1"
fi

# Record task start timestamp
date +%s > /tmp/rolling_zscore_anomaly_detection_start_ts

# Navigate to Graphite Dashboard
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/rolling_zscore_anomaly_detection_start_screenshot.png

echo "=== rolling_zscore_anomaly_detection setup complete ==="