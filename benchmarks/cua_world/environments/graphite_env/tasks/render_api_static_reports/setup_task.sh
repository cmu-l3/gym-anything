#!/bin/bash
echo "=== Setting up render_api_static_reports task ==="

source /workspace/scripts/task_utils.sh

# Ensure Graphite is ready
ensure_graphite_ready_for_task 120

# Clean up any potential artifacts from previous runs
rm -rf /home/ga/reports
rm -f /tmp/render_api_result.json

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Verify that the necessary metrics actually exist in Graphite
echo "Verifying real EC2 data metrics exist..."
for metric in "servers.ec2_instance_1.cpu.utilization" \
              "servers.ec2_instance_2.disk.write_bytes" \
              "servers.datacenter.machine_temperature"; do
    if metric_exists "$metric"; then
        echo "  Found required metric: $metric"
    else
        echo "  WARNING: Missing required metric: $metric"
    fi
done

# Start and focus Firefox to Graphite web UI as the starting state
focus_firefox
navigate_firefox_to "http://localhost/"
sleep 3

# Take initial screenshot showing environment state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== render_api_static_reports setup complete ==="