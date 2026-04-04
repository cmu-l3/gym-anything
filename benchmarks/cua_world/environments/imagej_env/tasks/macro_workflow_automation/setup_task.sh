#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Macro Workflow Automation Task ==="

# Define paths
MACRO_DIR="/home/ga/ImageJ_Data/macros"
MACRO_FILE="$MACRO_DIR/standard_protocol.ijm"

# Ensure clean state
echo "Cleaning up previous state..."
kill_fiji
sleep 2

# Create directories
mkdir -p "$MACRO_DIR"
chown -R ga:ga "/home/ga/ImageJ_Data"

# Remove any existing target file to ensure we detect new creation
rm -f "$MACRO_FILE"
rm -f /tmp/verification_results.csv
rm -f /tmp/macro_test.log

# Record task start time
date +%s > /tmp/task_start_time

# Launch Fiji
echo "Launching Fiji..."
launch_fiji
sleep 5

# Wait for Fiji window
wait_for_fiji 60

# Maximize and focus
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="