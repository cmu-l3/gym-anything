#!/bin/bash
echo "=== Setting up cacti_style_legacy_migration task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/cacti_style_legacy_migration_result.json 2>/dev/null || true
rm -f /tmp/cacti_style_legacy_migration_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name (ensure clean initial state)
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'NOC Legacy View'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'NOC Legacy View' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify required metrics exist
echo "Checking for required metrics..."
for metric in "servers.ec2_instance_1.cpu.utilization" \
              "servers.ec2_instance_1.network.bytes_in" \
              "servers.ec2_instance_1.disk.write_bytes" \
              "servers.datacenter.machine_temperature"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Record task start timestamp (anti-gaming)
date +%s > /tmp/cacti_style_legacy_migration_start_ts

# Navigate Firefox to the Graphite Dashboard page
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/cacti_style_legacy_migration_start_screenshot.png

echo "=== cacti_style_legacy_migration setup complete ==="