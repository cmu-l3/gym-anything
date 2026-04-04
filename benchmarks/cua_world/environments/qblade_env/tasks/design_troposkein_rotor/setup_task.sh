#!/bin/bash
set -e
echo "=== Setting up design_troposkein_rotor task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists
mkdir -p /home/ga/Documents/projects
chown ga:ga /home/ga/Documents/projects

# Remove any previous output file to ensure fresh creation
rm -f /home/ga/Documents/projects/troposkein_rotor.wpa 2>/dev/null || true

# Ensure QBlade is running
if ! pgrep -f "QBlade" > /dev/null; then
    echo "Launching QBlade..."
    launch_qblade
    
    # Wait for window
    wait_for_qblade 30
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="