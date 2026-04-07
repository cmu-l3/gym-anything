#!/bin/bash
echo "=== Setting up cumulative_transfer_reporting task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files
rm -f /tmp/cumulative_transfer_reporting_result.json 2>/dev/null || true
rm -f /tmp/cumulative_transfer_reporting_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Quarterly Ops Review'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Quarterly Ops Review' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify metrics exist
echo "Checking required metrics..."
for metric in "servers.ec2_instance_1.network.bytes_in" \
              "servers.load_balancer.requests.count" \
              "servers.ec2_instance_1.disk.write_bytes" \
              "servers.ec2_instance_2.disk.write_bytes"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Record task start timestamp
date +%s > /tmp/cumulative_transfer_reporting_start_ts

# Navigate to Graphite Dashboard
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/cumulative_transfer_reporting_start_screenshot.png

echo "=== cumulative_transfer_reporting setup complete ==="