#!/bin/bash
echo "=== Setting up workload_burstiness_index task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/workload_burstiness_index_result.json 2>/dev/null || true
rm -f /tmp/workload_burstiness_index_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name (ensure clean initial state)
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Workload Burstiness Index'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Workload Burstiness Index' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify required metrics exist
echo "Checking for required metrics..."
for metric in "servers.ec2_instance_1.cpu.utilization" \
              "servers.rds_database.cpu.utilization" \
              "servers.ec2_instance_1.network.bytes_in"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Record task start timestamp
date +%s > /tmp/workload_burstiness_index_start_ts

# Navigate Firefox to the Graphite Dashboard page
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/workload_burstiness_index_start_screenshot.png

echo "=== workload_burstiness_index setup complete ==="