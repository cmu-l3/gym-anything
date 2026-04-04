#!/bin/bash
echo "=== Setting up create_business_model_canvas task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous attempts
rm -f /home/ga/Documents/fraud_shield_bmc.eddx
rm -f /home/ga/Documents/fraud_shield_bmc.png
mkdir -p /home/ga/Documents

# Kill any existing EdrawMax processes to ensure a clean start
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Launch EdrawMax fresh (opens to Home/New screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Banners)
dismiss_edrawmax_dialogs

# Maximize the window for better agent visibility
maximize_edrawmax

# Take a screenshot to record the initial state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="
echo "EdrawMax is open. Ready for agent to create the Business Model Canvas."