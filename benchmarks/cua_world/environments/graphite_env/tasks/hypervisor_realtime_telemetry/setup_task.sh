#!/bin/bash
echo "=== Setting up hypervisor_realtime_telemetry task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files
rm -f /tmp/hypervisor_realtime_telemetry_result.json 2>/dev/null || true
rm -f /tmp/hypervisor_realtime_telemetry_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Hypervisor Telemetry'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Hypervisor Telemetry' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify collectd metrics exist
echo "Checking collectd metrics..."
if metric_exists "collectd.*.memory.*"; then
    echo "  Found: collectd memory metrics"
else
    echo "  WARNING: Missing collectd memory metrics"
fi

if metric_exists "collectd.*.cpu.*.cpu-user"; then
    echo "  Found: collectd cpu metrics"
else
    echo "  WARNING: Missing collectd cpu metrics"
fi

if metric_exists "collectd.*.load.load.*"; then
    echo "  Found: collectd load metrics"
else
    echo "  WARNING: Missing collectd load metrics"
fi

# Record task start timestamp
date +%s > /tmp/hypervisor_realtime_telemetry_start_ts

# Navigate to Graphite Dashboard
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/hypervisor_realtime_telemetry_start_screenshot.png

echo "=== hypervisor_realtime_telemetry setup complete ==="