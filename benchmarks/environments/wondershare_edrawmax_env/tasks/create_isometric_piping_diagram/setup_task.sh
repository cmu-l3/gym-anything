#!/bin/bash
set -e
echo "=== Setting up create_isometric_piping_diagram task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/Diagrams
rm -f /home/ga/Diagrams/cooling_loop_iso.eddx
rm -f /home/ga/Diagrams/cooling_loop_iso.png

# Kill any running EdrawMax instances to ensure clean state
kill_edrawmax

# Launch EdrawMax (opens to Home/New screen)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for EdrawMax to fully load
wait_for_edrawmax 90

# Dismiss startup dialogs (Account Login, File Recovery, Banners)
dismiss_edrawmax_dialogs

# Maximize the window for visibility
maximize_edrawmax

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="