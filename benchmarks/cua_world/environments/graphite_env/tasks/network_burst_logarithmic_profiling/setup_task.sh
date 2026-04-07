#!/bin/bash
echo "=== Setting up network_burst_logarithmic_profiling task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/network_burst_logarithmic_profiling_result.json 2>/dev/null || true
rm -f /tmp/network_burst_logarithmic_profiling_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name to ensure a clean slate
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Network Burst Profiling'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Network Burst Profiling' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify required metric exists
echo "Checking for required network metrics..."
if metric_exists "servers.ec2_instance_1.network.bytes_in"; then
    echo "  Found: servers.ec2_instance_1.network.bytes_in"
else
    echo "  WARNING: Missing: servers.ec2_instance_1.network.bytes_in"
fi

# Record task start timestamp for anti-gaming
date +%s > /tmp/network_burst_logarithmic_profiling_start_ts

# Navigate Firefox to the Graphite Dashboard page
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot showing clean state
take_screenshot /tmp/network_burst_logarithmic_profiling_start_screenshot.png

echo "=== network_burst_logarithmic_profiling setup complete ==="