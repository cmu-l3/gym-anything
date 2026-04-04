#!/bin/bash
echo "=== Setting up sysarch_aws_cloud_architecture task ==="

source /workspace/scripts/task_utils.sh

# Kill any running EdrawMax instances
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Remove any leftover output file from previous runs
rm -f /home/ga/aws_cloud_architecture.eddx 2>/dev/null || true

# Record task start timestamp AFTER cleanup
date +%s > /tmp/sysarch_aws_cloud_architecture_start_ts

# Launch EdrawMax fresh (opens to home/new screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take a screenshot to verify start state
sleep 2
take_screenshot /tmp/sysarch_aws_cloud_architecture_start.png
echo "Start state screenshot saved to /tmp/sysarch_aws_cloud_architecture_start.png"

echo "=== sysarch_aws_cloud_architecture task setup complete ==="
echo "EdrawMax is open. Agent should design an AWS 3-tier architecture and save as /home/ga/aws_cloud_architecture.eddx"
