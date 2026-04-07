#!/bin/bash
echo "=== Setting up capacity_planning_percentile_report task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/capacity_planning_percentile_report_result.json 2>/dev/null || true
rm -f /tmp/capacity_planning_percentile_report_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Capacity Planning Q4'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Capacity Planning Q4' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify fleet CPU metrics exist
echo "Checking EC2 fleet CPU metrics..."
for metric in "servers.ec2_instance_1.cpu.utilization" \
              "servers.ec2_instance_2.cpu.utilization" \
              "servers.ec2_instance_3.cpu.cloudwatch_utilization"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Record task start timestamp
date +%s > /tmp/capacity_planning_percentile_report_start_ts

# Navigate Firefox to Graphite Dashboard
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/capacity_planning_percentile_report_start_screenshot.png

echo "=== capacity_planning_percentile_report setup complete ==="
