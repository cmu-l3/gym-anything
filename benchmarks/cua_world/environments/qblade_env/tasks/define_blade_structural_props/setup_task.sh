#!/bin/bash
set -e
echo "=== Setting up Define Blade Structural Properties Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous artifacts
rm -f /home/ga/Documents/projects/structural_design.wpa
rm -f /home/ga/Documents/blade_mass.txt
rm -f /tmp/task_result.json
rm -f /tmp/task_final.png

# 3. Ensure directories exist
mkdir -p /home/ga/Documents/projects
mkdir -p /home/ga/Documents/airfoils

# 4. Launch QBlade
# We launch it clean (no project loaded)
echo "Launching QBlade..."
launch_qblade

# 5. Wait for window and maximize
wait_for_qblade 30
sleep 2

# Find QBlade window ID and maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "qblade" | cut -d' ' -f1 | head -1)
if [ -n "$WID" ]; then
    echo "Maximizing QBlade window $WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 wmctrl -i -a "$WID"
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="