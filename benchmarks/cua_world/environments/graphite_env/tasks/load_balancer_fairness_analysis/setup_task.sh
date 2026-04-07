#!/bin/bash
echo "=== Setting up load_balancer_fairness_analysis task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files
rm -f /tmp/load_balancer_fairness_analysis_result.json 2>/dev/null || true
rm -f /tmp/load_balancer_fairness_analysis_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Load Balancer Fairness'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Load Balancer Fairness' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify the required metrics exist
echo "Checking required metrics..."
for metric in "servers.ec2_instance_1.network.bytes_in" \
              "servers.ec2_instance_2.network.bytes_in" \
              "servers.ec2_instance_1.disk.write_bytes" \
              "servers.ec2_instance_2.disk.write_bytes" \
              "servers.ec2_instance_1.cpu.utilization" \
              "servers.ec2_instance_2.cpu.utilization"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Record task start timestamp
date +%s > /tmp/load_balancer_fairness_analysis_start_ts

# Navigate to Graphite Dashboard
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/load_balancer_fairness_analysis_start_screenshot.png

echo "=== load_balancer_fairness_analysis setup complete ==="