#!/bin/bash
set -e
echo "=== Setting up prepare_multi_re_polar_dataset ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up previous artifacts
echo "Cleaning up directories..."
rm -rf /home/ga/Documents/polars
rm -rf /home/ga/Documents/projects/re_dataset_study.wpa
mkdir -p /home/ga/Documents/polars
mkdir -p /home/ga/Documents/projects

# Set permissions
chown -R ga:ga /home/ga/Documents/polars
chown -R ga:ga /home/ga/Documents/projects

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Launch QBlade
echo "Launching QBlade..."
launch_qblade

# 4. Wait for window
wait_for_qblade 30

# 5. Maximize window (critical for visual interaction)
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="