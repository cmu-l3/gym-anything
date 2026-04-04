#!/bin/bash
set -euo pipefail

echo "=== Setting up matrix_ols_manual task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
GRETL_OUTPUT_DIR="/home/ga/Documents/gretl_output"
rm -rf "$GRETL_OUTPUT_DIR"
mkdir -p "$GRETL_OUTPUT_DIR"
chown ga:ga "$GRETL_OUTPUT_DIR"

# Restore fresh dataset
restore_dataset "food.gdt" "/home/ga/Documents/gretl_data/food.gdt"

# Launch Gretl with the dataset
# We use the utility function which handles display, user, and window waiting
launch_gretl "/home/ga/Documents/gretl_data/food.gdt" "/home/ga/gretl_matrix_ols.log"

# Wait for Gretl to initialize
wait_for_gretl 60

# Wait a bit for the UI to be fully ready
sleep 5

# Dismiss any potential startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize and focus
maximize_gretl
focus_gretl

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Gretl launched with food.gdt"