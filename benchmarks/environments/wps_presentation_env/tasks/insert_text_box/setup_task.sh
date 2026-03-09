#!/bin/bash
echo "=== Setting up insert_text_box task ==="

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

# Navigate to slide 2
sleep 2
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key ctrl+Home 2>/dev/null || true
sleep 0.5
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Page_Down 2>/dev/null || true
sleep 1

echo "=== insert_text_box task setup complete ==="
echo "WPS Presentation is open with performance.pptx on slide 2"
