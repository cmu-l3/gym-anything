#!/bin/bash
echo "=== Setting up statsd_application_telemetry task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files
rm -f /tmp/statsd_application_telemetry_result.json 2>/dev/null || true
rm -f /tmp/statsd_application_telemetry_dashboards.json 2>/dev/null || true
rm -f /tmp/statsd_application_telemetry_data.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name to ensure clean start
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Payment Gateway'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Payment Gateway' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify ec2 CPU metric exists
echo "Checking EC2 metric for correlation graph..."
if metric_exists "servers.ec2_instance_1.cpu.utilization"; then
    echo "  Found: servers.ec2_instance_1.cpu.utilization"
else
    echo "  WARNING: Missing: servers.ec2_instance_1.cpu.utilization"
fi

# Record task start timestamp
date +%s > /tmp/statsd_application_telemetry_start_ts

# Navigate Firefox to Graphite Dashboard
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/statsd_application_telemetry_start_screenshot.png

echo "=== statsd_application_telemetry setup complete ==="