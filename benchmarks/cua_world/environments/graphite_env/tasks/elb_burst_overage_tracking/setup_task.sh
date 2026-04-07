#!/bin/bash
echo "=== Setting up elb_burst_overage_tracking task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/elb_burst_overage_tracking_result.json 2>/dev/null || true
rm -f /tmp/elb_burst_overage_tracking_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name (ensure clean initial state)
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'ELB Burst Overage Tracking'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'ELB Burst Overage Tracking' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify required ELB metric exists
echo "Checking for required metrics..."
if metric_exists "servers.load_balancer.requests.count"; then
    echo "  Found: servers.load_balancer.requests.count"
else
    echo "  WARNING: Missing: servers.load_balancer.requests.count"
fi

# Record task start timestamp
date +%s > /tmp/elb_burst_overage_tracking_start_ts

# Navigate Firefox to the Graphite Dashboard page
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/elb_burst_overage_tracking_start_screenshot.png

echo "=== elb_burst_overage_tracking setup complete ==="