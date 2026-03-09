#!/bin/bash
echo "=== Setting up STRIDE Threat Model task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up previous run artifacts
rm -f /home/ga/Documents/threat_model.eddx 2>/dev/null || true
rm -f /home/ga/Documents/threat_model.png 2>/dev/null || true

# Ensure EdrawMax is not running
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Launch EdrawMax to the home screen (no specific file loaded)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for application to load
wait_for_edrawmax 90

# Dismiss standard startup dialogs (Account Login, File Recovery, Banners)
dismiss_edrawmax_dialogs

# Maximize the window for visibility
maximize_edrawmax

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot captured: /tmp/task_initial.png"

echo "=== Task setup complete ==="