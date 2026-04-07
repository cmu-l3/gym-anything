#!/bin/bash
# set -euo pipefail

echo "=== Setting up create_scatter_plot_iris task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# -------------------------------------------------------
# 1. Ensure Iris dataset is available
# -------------------------------------------------------
DATA_FILE="/home/ga/Documents/data/iris.csv"
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Iris dataset not found at $DATA_FILE"
    # Try to copy from mounted data
    if [ -f /workspace/data/iris.csv ]; then
        mkdir -p /home/ga/Documents/data
        cp /workspace/data/iris.csv "$DATA_FILE"
        chown ga:ga "$DATA_FILE"
        echo "Copied Iris dataset from mounted data"
    else
        echo "FATAL: No Iris data available"
        exit 1
    fi
fi

echo "Iris dataset available: $(wc -l < "$DATA_FILE") lines"

# -------------------------------------------------------
# 2. Launch KNIME
# -------------------------------------------------------
launch_knime
sleep 3

# -------------------------------------------------------
# 3. Create a new empty workflow named "Iris Visualization"
# -------------------------------------------------------
create_new_workflow "Iris Visualization"

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

echo "=== create_scatter_plot_iris task setup complete ==="
echo "Agent should see: KNIME workflow editor with empty 'Iris Visualization' workflow"
echo "Node Repository is visible on the left with available nodes"
echo "Task: Create scatter plot of Iris data (sepal_length vs petal_length)"
