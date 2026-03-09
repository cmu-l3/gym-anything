#!/bin/bash
set -e
echo "=== Setting up blade_modal_analysis task ==="

# 1. Clean up previous artifacts
rm -f /home/ga/Documents/projects/beam_modal.wpa 2>/dev/null || true
rm -f /home/ga/Documents/modal_results.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 2. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 3. Ensure directories exist
mkdir -p /home/ga/Documents/projects
mkdir -p /home/ga/Documents/airfoils
chown -R ga:ga /home/ga/Documents/

# 4. Launch QBlade
echo "Launching QBlade..."
source /workspace/scripts/task_utils.sh
launch_qblade

# 5. Wait for QBlade window
wait_for_qblade 30

# 6. Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="