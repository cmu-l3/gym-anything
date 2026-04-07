#!/bin/bash
echo "=== Setting up network_routing_asymmetry_dashboard task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files
rm -f /tmp/network_routing_asymmetry_dashboard_result.json 2>/dev/null || true
rm -f /tmp/network_routing_asymmetry_dashboard_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Network Routing Asymmetry'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Network Routing Asymmetry' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify the primary metrics exist
echo "Checking required metrics..."
for metric in "servers.web_traffic.speed_sensor_1" "servers.web_traffic.speed_sensor_2"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Record task start timestamp
date +%s > /tmp/network_routing_asymmetry_dashboard_start_ts

# Navigate to Graphite Dashboard
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/network_routing_asymmetry_dashboard_start_screenshot.png

echo "=== network_routing_asymmetry_dashboard setup complete ==="