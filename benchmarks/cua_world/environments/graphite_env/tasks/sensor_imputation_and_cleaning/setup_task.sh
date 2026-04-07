#!/bin/bash
echo "=== Setting up sensor_imputation_and_cleaning task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready and has ingested metrics
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/sensor_imputation_and_cleaning_result.json 2>/dev/null || true
rm -f /tmp/sensor_imputation_and_cleaning_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name (ensure clean initial state)
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Cleaned Telemetry'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Cleaned Telemetry' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify required metrics exist
echo "Checking for required metrics..."
for metric in "servers.web_traffic.speed_sensor_1" \
              "servers.datacenter.machine_temperature" \
              "servers.ec2_instance_1.disk.write_bytes" \
              "servers.ec2_instance_1.cpu.utilization"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Record task start timestamp
date +%s > /tmp/sensor_imputation_and_cleaning_start_ts

# Navigate Firefox to the Graphite Dashboard page
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot for VLM / debugging purposes
take_screenshot /tmp/sensor_imputation_and_cleaning_start_screenshot.png

echo "=== sensor_imputation_and_cleaning setup complete ==="