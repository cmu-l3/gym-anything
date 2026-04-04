#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up RESET Functional Form Test task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running gretl instances
kill_gretl

# Clean previous output
rm -f /home/ga/Documents/gretl_output/reset_comparison.txt
mkdir -p /home/ga/Documents/gretl_output
chown ga:ga /home/ga/Documents/gretl_output

# Restore clean food.gdt dataset
restore_dataset "food.gdt" "/home/ga/Documents/gretl_data/food.gdt"

# Record dataset timestamp to detect modifications
stat -c%Y "/home/ga/Documents/gretl_data/food.gdt" > /tmp/dataset_initial_mtime.txt

# Launch gretl with food.gdt
launch_gretl "/home/ga/Documents/gretl_data/food.gdt" "/home/ga/gretl_reset_task.log"

# Wait for gretl window
wait_for_gretl 60 || true
sleep 5

# Dismiss any startup dialogs
for i in {1..3}; do
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        xdotool key Escape 2>/dev/null || true
    sleep 1
done

# Maximize and focus
maximize_gretl
focus_gretl
sleep 2

# Take initial screenshot
mkdir -p /tmp/task_evidence
take_screenshot /tmp/task_evidence/initial_state.png

echo "=== RESET Functional Form Test task setup complete ==="