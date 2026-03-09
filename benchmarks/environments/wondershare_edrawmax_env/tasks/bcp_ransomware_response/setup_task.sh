#!/bin/bash
echo "=== Setting up bcp_ransomware_response task ==="

source /workspace/scripts/task_utils.sh

# Kill any running EdrawMax instances
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Remove any leftover output file from previous runs (anti-gaming: ensures do-nothing test fails)
rm -f /home/ga/ransomware_ir_flowchart.eddx 2>/dev/null || true

# Record task start timestamp AFTER cleanup
date +%s > /tmp/bcp_ransomware_response_start_ts

# Launch EdrawMax fresh (opens to home/new screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login and File Recovery banner)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# Take a screenshot to verify start state
sleep 2
take_screenshot /tmp/bcp_ransomware_response_start.png
echo "Start state screenshot saved to /tmp/bcp_ransomware_response_start.png"

echo "=== bcp_ransomware_response task setup complete ==="
echo "EdrawMax is open. Agent should create a ransomware IR swimlane diagram and save as /home/ga/ransomware_ir_flowchart.eddx"
