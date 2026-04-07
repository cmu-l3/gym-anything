#!/bin/bash
echo "=== Setting up wow_deployment_baseline task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is fully up and running
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/wow_deployment_baseline_result.json 2>/dev/null || true
rm -f /tmp/wow_deployment_baseline_dashboards.json 2>/dev/null || true

# Clean up any pre-existing dashboard with the target name
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'WoW Deployment Baseline'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'WoW Deployment Baseline' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify the required metrics exist
echo "Checking for required time-series metrics..."
for metric in "servers.web_traffic.speed_sensor_1" \
              "servers.load_balancer.requests.count" \
              "servers.rds_database.cpu.utilization"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Record task start timestamp for anti-gaming verifications
date +%s > /tmp/wow_deployment_baseline_start_ts

# Navigate Firefox to the Graphite Dashboard interface
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take an initial screenshot to confirm the setup state
take_screenshot /tmp/wow_deployment_baseline_start_screenshot.png

echo "=== wow_deployment_baseline setup complete ==="