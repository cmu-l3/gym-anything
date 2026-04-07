#!/bin/bash
echo "=== Setting up peak_load_analysis task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/peak_load_analysis_result.json 2>/dev/null || true
rm -f /tmp/peak_load_analysis_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name (ensure clean initial state)
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Peak Load Analysis'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Peak Load Analysis' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify required metrics exist
echo "Checking for required metrics..."
for metric in "servers.ec2_instance_1.cpu.utilization" \
              "servers.ec2_instance_2.cpu.utilization" \
              "servers.ec2_instance_3.cpu.cloudwatch_utilization"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/peak_load_analysis_start_ts

# Navigate Firefox to the Graphite Dashboard page
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot showing the initial state
take_screenshot /tmp/peak_load_analysis_start_screenshot.png

echo "=== peak_load_analysis setup complete ==="