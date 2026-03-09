#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up elasticity_hypothesis_script task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous artifacts
echo "Cleaning output directory..."
rm -rf /home/ga/Documents/gretl_output/*
mkdir -p /home/ga/Documents/gretl_output
chown ga:ga /home/ga/Documents/gretl_output

# 2. Ensure dataset is available and clean
echo "Restoring dataset..."
restore_dataset "food.gdt"

# 3. Launch Gretl with the dataset loaded
# This gives the agent a starting point, though the script they write might reload it
echo "Launching Gretl..."
kill_gretl
launch_gretl "/home/ga/Documents/gretl_data/food.gdt" "/home/ga/gretl_task.log"

# 4. Wait for window and configure
wait_for_gretl 60 || true
sleep 5

# Dismiss startup dialogs if any
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Maximize and focus
maximize_gretl
focus_gretl
sleep 1

# 5. Capture initial state
echo "Capturing initial screenshot..."
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="