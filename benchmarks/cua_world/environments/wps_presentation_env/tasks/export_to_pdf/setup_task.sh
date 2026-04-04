#!/bin/bash
echo "=== Setting up export_to_pdf task ==="

source /workspace/scripts/task_utils.sh

# Kill any running WPS instance
kill_wps

# Reset the presentation file to original clean state
reset_presentation

# Remove any previously generated PDF output to ensure clean state
rm -f /home/ga/Documents/presentations/performance.pdf
rm -f /home/ga/Documents/presentations/performance_output.pdf

# Launch WPS Presentation with the file
launch_wps_with_file "/home/ga/Documents/presentations/performance.pptx"

# Wait for WPS to fully load
wait_for_wps 45

# Maximize the window
maximize_wps

# Navigate to slide 1 so the full presentation is visible
sleep 2
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key ctrl+Home 2>/dev/null || true

echo "=== export_to_pdf task setup complete ==="
echo "WPS Presentation is open with performance.pptx"
echo "Expected PDF output: /home/ga/Documents/presentations/performance.pdf"
