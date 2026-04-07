#!/bin/bash
# set -euo pipefail

echo "=== Setting up import_and_explore_titanic_data task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# -------------------------------------------------------
# 1. Ensure Titanic dataset is available
# -------------------------------------------------------
DATA_FILE="/home/ga/Documents/data/titanic.csv"
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Titanic dataset not found at $DATA_FILE"
    # Try to copy from mounted data
    if [ -f /workspace/data/titanic.csv ]; then
        mkdir -p /home/ga/Documents/data
        cp /workspace/data/titanic.csv "$DATA_FILE"
        chown ga:ga "$DATA_FILE"
        echo "Copied Titanic dataset from mounted data"
    else
        echo "FATAL: No Titanic data available"
        exit 1
    fi
fi

echo "Titanic dataset available: $(wc -l < "$DATA_FILE") lines"

# -------------------------------------------------------
# 2. Launch KNIME
# -------------------------------------------------------
launch_knime
sleep 3

# -------------------------------------------------------
# 3. Create a new empty workflow named "Titanic Analysis"
# -------------------------------------------------------
create_new_workflow "Titanic Analysis"

# -------------------------------------------------------
# 4. Focus and ensure KNIME window is ready
# -------------------------------------------------------

# Click on center of screen to select desktop (dismiss any overlays)
DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
sleep 1

# Focus KNIME window
wid=$(get_knime_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Dismiss any remaining dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== import_and_explore_titanic_data task setup complete ==="
echo "Agent should see: KNIME workflow editor with empty 'Titanic Analysis' workflow"
echo "Node Repository is visible on the left with available nodes"
echo "Task: Import /home/ga/Documents/data/titanic.csv using a CSV Reader node"
