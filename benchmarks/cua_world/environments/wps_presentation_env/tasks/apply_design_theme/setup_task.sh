#!/bin/bash
echo "=== Setting up apply_design_theme task ==="

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

# Ensure we're on slide 1 so theme changes are visible
sleep 2
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key ctrl+Home 2>/dev/null || true

echo "=== apply_design_theme task setup complete ==="
echo "WPS Presentation is open with performance.pptx, ready to apply a design theme"
