#!/bin/bash
set -e
echo "=== Setting up extract_root_bending_moment task ==="

# 1. Clean up previous runs
rm -f /home/ga/Documents/projects/root_moment_report.txt
rm -f /tmp/task_result.json
rm -f /tmp/task_start_time.txt
rm -rf /home/ga/Documents/projects/temp_simulation*

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create projects directory if not exists
mkdir -p /home/ga/Documents/projects
chown ga:ga /home/ga/Documents/projects

# 4. Launch QBlade
echo "Launching QBlade..."
source /workspace/scripts/task_utils.sh

# Check if QBlade is already running, if not launch it
if ! is_qblade_running > /dev/null; then
    launch_qblade
    # Wait for window
    wait_for_qblade 30
fi

# 5. Ensure Window is maximized
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="