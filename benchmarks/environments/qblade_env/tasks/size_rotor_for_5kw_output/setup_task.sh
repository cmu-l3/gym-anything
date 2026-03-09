#!/bin/bash
set -e
echo "=== Setting up size_rotor_for_5kw_output task ==="

# 1. timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous runs
rm -f /home/ga/Documents/projects/sized_rotor_5kw.wpa
rm -f /home/ga/Documents/projects/final_simulation.txt
rm -f /home/ga/Documents/projects/sizing_result.txt
rm -f /tmp/task_result.json

# 3. Ensure QBlade is running
source /workspace/scripts/task_utils.sh

if ! pgrep -f "QBlade" > /dev/null; then
    echo "Starting QBlade..."
    launch_qblade
    sleep 5
fi

# 4. Wait for window
wait_for_qblade 30

# 5. Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="