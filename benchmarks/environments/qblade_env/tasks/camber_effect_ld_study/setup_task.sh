#!/bin/bash
set -e
echo "=== Setting up Camber Effect L/D Study ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous artifacts to ensure a fresh start
rm -f /home/ga/Documents/camber_study_report.txt
rm -f /home/ga/Documents/projects/camber_study.wpa
rm -f /tmp/task_result.json

# 2. Ensure directories exist
mkdir -p /home/ga/Documents/projects
chown -R ga:ga /home/ga/Documents

# 3. Launch QBlade (clean session)
# We don't load a specific project, just start the app
echo "Launching QBlade..."
launch_qblade

# 4. Wait for application window
wait_for_qblade 30

# 5. Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="