#!/bin/bash
set -e
echo "=== Setting up GARCH Volatility Inflation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming check)
date +%s > /tmp/task_start_time.txt

# Kill any running gretl instances
kill_gretl

# Ensure output directory exists and is clean
rm -rf /home/ga/Documents/gretl_output/*
mkdir -p /home/ga/Documents/gretl_output
chown -R ga:ga /home/ga/Documents/gretl_output

# Ensure usa.gdt exists in the user's data directory
DATASET_PATH="/home/ga/Documents/gretl_data/usa.gdt"

if [ ! -f "$DATASET_PATH" ]; then
    echo "Restoring usa.gdt..."
    restore_dataset "usa.gdt" "$DATASET_PATH" || \
    cp /opt/gretl_data/poe5/usa.gdt "$DATASET_PATH" 2>/dev/null || \
    echo "WARNING: usa.gdt could not be found!"
fi

# Set permissions
chown ga:ga "$DATASET_PATH"

# Launch Gretl with usa.gdt so the agent can inspect the data if needed
# (Even though the task is scripting, seeing the GUI helps context)
launch_gretl "$DATASET_PATH" "/home/ga/gretl_task.log"

# Wait for Gretl window
wait_for_gretl 60 || true
sleep 5

# Handle any startup dialogs
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

# Maximize and focus
maximize_gretl
focus_gretl

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Output directory: /home/ga/Documents/gretl_output/"
echo "Dataset: $DATASET_PATH"