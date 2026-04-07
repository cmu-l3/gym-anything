#!/bin/bash
echo "=== Setting up dynamic_bottleneck_triage task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready and populated with metrics
ensure_graphite_ready_for_task 120

# Remove stale result files from any previous runs
rm -f /tmp/dynamic_bottleneck_triage_result.json 2>/dev/null || true
rm -f /tmp/dynamic_bottleneck_triage_dashboards.json 2>/dev/null || true

# Delete any pre-existing dashboard with the target name to ensure clean state
docker exec graphite python3 - << 'PYEOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/graphite/storage/graphite.db')
    cursor = conn.cursor()
    cursor.execute("DELETE FROM dashboard_dashboard WHERE name = 'Dynamic Bottleneck Triage'")
    conn.commit()
    conn.close()
    print("Cleaned up any existing 'Dynamic Bottleneck Triage' dashboard")
except Exception as e:
    print(f"Note: {e}")
PYEOF

# Verify all required fleet metrics exist
echo "Checking EC2 fleet metrics..."
for metric in "servers.ec2_instance_1.cpu.utilization" \
              "servers.ec2_instance_2.cpu.utilization" \
              "servers.ec2_instance_3.cpu.cloudwatch_utilization" \
              "servers.ec2_instance_1.disk.write_bytes"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Record task start timestamp (Anti-gaming: dashboard must be updated AFTER this)
date +%s > /tmp/dynamic_bottleneck_triage_start_ts

# Navigate Firefox to the Graphite Dashboard page
focus_firefox
navigate_firefox_to "http://localhost/dashboard/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/dynamic_bottleneck_triage_start_screenshot.png

echo "=== dynamic_bottleneck_triage setup complete ==="