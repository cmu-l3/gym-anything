#!/bin/bash
set -e
echo "=== Setting up assess_vawt_strut_drag_impact ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure clean state
rm -f /home/ga/Documents/projects/vawt_strut_study.wpa
rm -f /home/ga/Documents/projects/strut_loss_report.txt
rm -f /tmp/task_result.json

# Ensure directories exist
mkdir -p /home/ga/Documents/projects
chown -R ga:ga /home/ga/Documents/projects

# Launch QBlade if not running
if ! is_qblade_running > /dev/null; then
    echo "Starting QBlade..."
    launch_qblade
    
    # Wait for window
    wait_for_qblade 30
fi

# Ensure window is maximized and focused
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="