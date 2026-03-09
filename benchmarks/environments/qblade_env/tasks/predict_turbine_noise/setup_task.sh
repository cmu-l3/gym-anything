#!/bin/bash
set -e
echo "=== Setting up predict_turbine_noise task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/projects
chown ga:ga /home/ga/Documents/projects

# Clean up any previous task artifacts
rm -f /home/ga/Documents/noise_spectrum_output.txt
rm -f /home/ga/Documents/projects/turbine_noise_analysis.wpa
rm -f /tmp/task_result.json

# Record initial file counts for later comparison
ls -1 /home/ga/Documents/sample_projects/*.wpa 2>/dev/null | wc -l > /tmp/initial_sample_count.txt

# Launch QBlade if not running
if ! is_qblade_running > /dev/null; then
    echo "Launching QBlade..."
    launch_qblade
    
    # Wait for QBlade window
    wait_for_qblade 30
fi

# Ensure window is maximized for best visibility
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="