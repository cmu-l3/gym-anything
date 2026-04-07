#!/bin/bash
echo "=== Setting up datacenter_thermal_analysis task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready and metrics are loaded
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/datacenter_thermal_analysis_result.json 2>/dev/null || true
rm -f /tmp/datacenter_thermal_analysis_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name (ensure clean initial state)
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Datacenter Thermal Analysis'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Datacenter Thermal Analysis' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify required metrics exist in Graphite before starting
echo "Checking for required metrics..."
for metric in "servers.datacenter.machine_temperature" \
              "servers.ec2_instance_1.cpu.utilization"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Record task start timestamp (anti-gaming)
date +%s > /tmp/datacenter_thermal_analysis_start_ts

# Navigate Firefox to the Graphite Dashboard page
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot as evidence of starting state
take_screenshot /tmp/datacenter_thermal_analysis_start_screenshot.png

echo "=== datacenter_thermal_analysis setup complete ==="