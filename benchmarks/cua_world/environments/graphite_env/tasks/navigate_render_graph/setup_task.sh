#!/bin/bash
echo "=== Setting up navigate_render_graph task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Verify the target metric exists
echo "Checking for target metric: servers.ec2_instance_1.cpu.utilization"
if metric_exists "servers.ec2_instance_1.cpu.*"; then
    echo "Target metric found"
else
    echo "WARNING: Target metric not yet available, data may still be loading"
fi

# Record initial state for verification
date +%s > /tmp/task_start_time

# Count existing metrics
METRIC_COUNT=$(get_metric_count)
echo "Available metrics at task start: $METRIC_COUNT"
echo "$METRIC_COUNT" > /tmp/initial_metric_count

# Navigate Firefox to Graphite homepage (the tree browser view)
focus_firefox
navigate_firefox_to "http://localhost/"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== navigate_render_graph task setup complete ==="
echo "Agent should navigate the tree: servers > ec2_instance_1 > cpu > utilization"
