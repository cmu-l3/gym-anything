#!/bin/bash
set -e
echo "=== Setting up LOO Cross-Validation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
OUTPUT_DIR="/home/ga/Documents/gretl_output"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Restore fresh food.gdt dataset
echo "Restoring dataset..."
restore_dataset "food.gdt"

# Launch Gretl with the dataset
echo "Launching Gretl..."
launch_gretl "/home/ga/Documents/gretl_data/food.gdt" "/home/ga/gretl_loo_task.log"

# Wait for Gretl to start
wait_for_gretl 60

# Maximize window
maximize_gretl

# Focus window
focus_gretl

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="