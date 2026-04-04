#!/bin/bash
echo "=== Setting up edit_title_slide task ==="

source /workspace/scripts/task_utils.sh

# Kill any running WPS instance
kill_wps

# Reset the presentation file to original clean state
reset_presentation

# Launch WPS Presentation with the file
launch_wps_with_file "/home/ga/Documents/presentations/performance.pptx"

# Wait for WPS to fully load
wait_for_wps 45

# Maximize the window
maximize_wps

# Ensure we're on slide 1 (Ctrl+Home)
sleep 2
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key ctrl+Home 2>/dev/null || true

echo "=== edit_title_slide task setup complete ==="
echo "WPS Presentation is open with performance.pptx on slide 1"
