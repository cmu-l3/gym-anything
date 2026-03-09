#!/bin/bash
echo "=== Setting up create_landscape_design_plan task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running EdrawMax instances to ensure clean state
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Remove any leftover output files from previous runs to prevent false positives
rm -f /home/ga/Documents/Johnson_Landscape_Plan.eddx 2>/dev/null || true
rm -f /home/ga/Documents/Johnson_Landscape_Plan.png 2>/dev/null || true

# Launch EdrawMax (opens to Home/New screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load (it's a heavy app)
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, promotional banners)
dismiss_edrawmax_dialogs

# Maximize the window for best agent visibility
maximize_edrawmax

# Take a screenshot to verify start state
take_screenshot /tmp/task_initial.png
echo "Start state screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="
echo "EdrawMax is open. Agent needs to create a garden plan and save to ~/Documents/Johnson_Landscape_Plan.eddx and .png"