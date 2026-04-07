#!/bin/bash
echo "=== Setting up fleet_load_imbalance_detector task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/fleet_load_imbalance_detector_result.json 2>/dev/null || true
rm -f /tmp/fleet_load_imbalance_detector_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name (ensure clean initial state)
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Load Balancer Equity'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Load Balancer Equity' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify required metrics exist
echo "Checking for required metrics..."
for metric in "servers.ec2_instance_1.cpu.utilization" \
              "servers.web_traffic.speed_sensor_1" \
              "servers.web_traffic.speed_sensor_2"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Record task start timestamp
date +%s > /tmp/fleet_load_imbalance_detector_start_ts

# Navigate Firefox to the Graphite Dashboard page
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/fleet_load_imbalance_detector_start_screenshot.png

echo "=== fleet_load_imbalance_detector setup complete ==="