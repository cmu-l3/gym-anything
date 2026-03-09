#!/bin/bash
echo "=== Setting up design_award_certificate task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure clean state: Remove any previous attempts
rm -f /home/ga/Documents/certificate_jordan_lee.eddx
rm -f /home/ga/Documents/certificate_jordan_lee.pdf
rm -f /home/ga/Documents/certificate_jordan_lee.png

# Ensure Documents directory exists
mkdir -p /home/ga/Documents

# Kill any running EdrawMax instances to ensure fresh start
echo "Killing any existing EdrawMax processes..."
kill_edrawmax

# Launch EdrawMax fresh (opens to home/new screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login and File Recovery)
dismiss_edrawmax_dialogs

# Maximize the window for better agent visibility
maximize_edrawmax

# Take a screenshot of initial state (for evidence)
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="