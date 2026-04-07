#!/bin/bash
echo "=== Setting up anomaly_baseline_forecasting task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files
rm -f /tmp/anomaly_baseline_forecasting_result.json 2>/dev/null || true
rm -f /tmp/anomaly_baseline_forecasting_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Anomaly Detection'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Anomaly Detection' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify the primary metric for this task exists
echo "Checking required metric for Holt-Winters..."
if metric_exists "servers.ec2_instance_2.cpu.utilization"; then
    echo "  Found: servers.ec2_instance_2.cpu.utilization"
else
    echo "  WARNING: Missing: servers.ec2_instance_2.cpu.utilization"
fi

# Record task start timestamp
date +%s > /tmp/anomaly_baseline_forecasting_start_ts

# Navigate to Graphite Dashboard
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/anomaly_baseline_forecasting_start_screenshot.png

echo "=== anomaly_baseline_forecasting setup complete ==="
