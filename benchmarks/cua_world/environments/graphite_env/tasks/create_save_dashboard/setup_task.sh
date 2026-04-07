#!/bin/bash
echo "=== Setting up create_save_dashboard task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Verify required metrics exist
echo "Checking for required metrics..."
for metric in "servers.ec2_instance_1.cpu.utilization" "servers.ec2_instance_1.disk.write_bytes"; do
    if metric_exists "$metric"; then
        echo "  Found: $metric"
    else
        echo "  WARNING: Missing: $metric"
    fi
done

# Record initial state
date +%s > /tmp/task_start_time

# Check existing dashboards (should be none initially)
EXISTING_DASHBOARDS=$(curl -s "http://localhost/dashboard/find/" 2>/dev/null || echo "{}")
echo "Existing dashboards: $EXISTING_DASHBOARDS"
echo "$EXISTING_DASHBOARDS" > /tmp/initial_dashboards.json

# Navigate Firefox to the Graphite Dashboard page
focus_firefox
navigate_firefox_to "http://localhost/dashboard"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== create_save_dashboard task setup complete ==="
echo "Agent should: Create dashboard 'Server Monitoring' with CPU and disk graphs"
