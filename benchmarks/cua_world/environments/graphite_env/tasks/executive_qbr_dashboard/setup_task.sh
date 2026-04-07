#!/bin/bash
echo "=== Setting up executive_qbr_dashboard task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready and containers are running
ensure_graphite_ready_for_task 120

# Remove stale result files from prior runs
rm -f /tmp/executive_qbr_dashboard_result.json 2>/dev/null || true
rm -f /tmp/executive_qbr_dashboard_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name to ensure a clean slate
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'QBR Infrastructure Summary'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'QBR Infrastructure Summary' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify the required metrics are available and indexed
echo "Checking required metrics..."
for metric in "servers.ec2_instance_1.cpu.utilization" \
              "servers.ec2_instance_1.disk.write_bytes" \
              "servers.ec2_instance_2.disk.write_bytes"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/executive_qbr_dashboard_start_ts

# Navigate to the Graphite Dashboard application
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take an initial screenshot showing the initial browser state
take_screenshot /tmp/executive_qbr_dashboard_start_screenshot.png

echo "=== executive_qbr_dashboard setup complete ==="