#!/bin/bash
echo "=== Setting up add_new_slide task ==="

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

# Navigate to the last slide so agent can see we're at the end
sleep 2
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key ctrl+End 2>/dev/null || true
sleep 1

echo "=== add_new_slide task setup complete ==="
echo "WPS Presentation is open with performance.pptx, positioned at last slide"
