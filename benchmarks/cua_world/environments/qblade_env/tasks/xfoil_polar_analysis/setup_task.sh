#!/bin/bash
echo "=== Setting up xfoil_polar_analysis task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up previous run artifacts
rm -f /home/ga/Documents/polar_analysis_output.txt
rm -f /home/ga/Documents/polar_summary.txt
rm -f /tmp/task_result.json

# Record initial state of QBlade processes
pgrep -f "QBlade" | wc -l > /tmp/initial_qblade_count.txt

# Launch QBlade
# We use the shared utility which handles finding the binary and setting library paths
echo "Launching QBlade..."
launch_qblade

# Wait for window to appear
wait_for_qblade 30

# Maximize window for better agent visibility
echo "Maximizing QBlade window..."
sleep 2
WID=$(DISPLAY=:1 wmctrl -l | grep -i "QBlade" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 wmctrl -ia "$WID"
fi

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="