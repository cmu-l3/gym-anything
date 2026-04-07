#!/bin/bash
echo "=== Setting up cross_tier_infrastructure_health task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Remove stale result files
rm -f /tmp/cross_tier_infrastructure_health_result.json 2>/dev/null || true
rm -f /tmp/cross_tier_infrastructure_health_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Infrastructure Health'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Infrastructure Health' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify all tier metrics exist
echo "Checking infrastructure tier metrics..."
for metric in "servers.ec2_instance_1.cpu.utilization" \
              "servers.rds_database.cpu.utilization" \
              "servers.load_balancer.requests.count" \
              "servers.ec2_instance_1.disk.write_bytes"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Record task start timestamp
date +%s > /tmp/cross_tier_infrastructure_health_start_ts

# Navigate to Graphite Dashboard
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/cross_tier_infrastructure_health_start_screenshot.png

echo "=== cross_tier_infrastructure_health setup complete ==="
