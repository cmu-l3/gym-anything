#!/bin/bash
set -e
echo "=== Setting up Create Value Chain Analysis task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (critical for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Clean up any previous run artifacts
rm -f /home/ga/Documents/ecotech_value_chain.eddx
rm -f /home/ga/Documents/ecotech_value_chain.png
mkdir -p /home/ga/Documents

# 3. Ensure EdrawMax is running and ready
echo "Checking EdrawMax state..."

# Kill existing instances to ensure fresh start
kill_edrawmax

# Launch EdrawMax to the home screen (no file loaded)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for window to appear and stabilize
wait_for_edrawmax 90

# Dismiss standard startup dialogs (Login, Recovery)
dismiss_edrawmax_dialogs

# Maximize window for visibility
maximize_edrawmax

# 4. Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="