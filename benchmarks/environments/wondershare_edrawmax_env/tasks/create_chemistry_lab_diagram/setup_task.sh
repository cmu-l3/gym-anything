#!/bin/bash
echo "=== Setting up create_chemistry_lab_diagram task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any existing EdrawMax instances to ensure clean state
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Remove any previous task artifacts
rm -f /home/ga/Documents/distillation_setup.eddx 2>/dev/null || true
rm -f /home/ga/Documents/distillation_setup.png 2>/dev/null || true

# Launch EdrawMax (no file argument -> opens Home/New screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Banners)
dismiss_edrawmax_dialogs

# Maximize the window (Critical for VLM visibility)
maximize_edrawmax

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="