#!/bin/bash
echo "=== Setting up network_traffic_rate_conversion task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/network_traffic_rate_conversion_result.json 2>/dev/null || true
rm -f /tmp/network_traffic_rate_conversion_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name to ensure a clean state
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Network Bandwidth Monitor'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Network Bandwidth Monitor' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify the network metric exists
echo "Checking EC2 network metric..."
if metric_exists "servers.ec2_instance_1.network.bytes_in"; then
    echo "  Found: servers.ec2_instance_1.network.bytes_in"
else
    echo "  WARNING: Missing: servers.ec2_instance_1.network.bytes_in"
fi

# Record task start timestamp
date +%s > /tmp/network_traffic_rate_conversion_start_ts

# Navigate Firefox to Graphite Dashboard
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/network_traffic_rate_conversion_start_screenshot.png

echo "=== network_traffic_rate_conversion setup complete ==="