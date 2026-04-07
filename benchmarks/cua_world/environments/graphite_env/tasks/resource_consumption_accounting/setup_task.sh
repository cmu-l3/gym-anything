#!/bin/bash
echo "=== Setting up resource_consumption_accounting task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/resource_consumption_accounting_result.json 2>/dev/null || true
rm -f /tmp/resource_consumption_accounting_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name to ensure clean initial state
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Resource Accounting'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Resource Accounting' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify required metrics exist in the data feed
echo "Checking for required metrics..."
for metric in "servers.ec2_instance_1.network.bytes_in" \
              "servers.ec2_instance_1.disk.write_bytes" \
              "servers.ec2_instance_2.disk.write_bytes"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing metric: $metric"
    fi
done

# Record task start timestamp (Anti-gaming measure)
date +%s > /tmp/resource_consumption_accounting_start_ts

# Navigate Firefox to the Graphite Dashboard page
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot showing the start state
take_screenshot /tmp/resource_consumption_accounting_start_screenshot.png

echo "=== resource_consumption_accounting setup complete ==="