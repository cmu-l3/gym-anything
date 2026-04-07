#!/bin/bash
echo "=== Setting up normalized_dependency_correlation task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files from previous runs
rm -f /tmp/normalized_dependency_correlation_result.json 2>/dev/null || true
rm -f /tmp/normalized_dependency_correlation_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Dependency Bottleneck Correlation'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Dependency Bottleneck Correlation' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify required metrics exist
echo "Checking required metrics for correlation..."
for metric in "servers.load_balancer.requests.count" \
              "servers.rds_database.cpu.utilization" \
              "servers.web_traffic.speed_sensor_1" \
              "servers.ec2_instance_1.cpu.utilization"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/normalized_dependency_correlation_start_ts

# Navigate Firefox to the Graphite Dashboard page
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot to capture clean starting state
take_screenshot /tmp/normalized_dependency_correlation_start_screenshot.png

echo "=== normalized_dependency_correlation setup complete ==="