#!/bin/bash
# Setup script for boattail_drag_reduction_retrofit task

echo "=== Setting up boattail_drag_reduction_retrofit task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="$ROCKETS_DIR/simple_model_rocket.ork"
EXPORTS_DIR="/home/ga/Documents/exports"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Verify source file exists
if [ ! -f "$SOURCE_ORK" ]; then
    echo "FATAL: Source file $SOURCE_ORK not found!"
    exit 1
fi

# Remove previous output files
rm -f "$EXPORTS_DIR/boattail_retrofit.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/boattail_report.txt" 2>/dev/null || true

# Record task start time for anti-gaming (file mtime checks)
date +%s > /tmp/task_start_time.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the baseline simple rocket
launch_openrocket "$SOURCE_ORK"
sleep 3

# Wait for application to load
wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot showing the baseline rocket loaded
take_screenshot /tmp/task_initial_state.png 2>/dev/null || true
echo "Initial screenshot saved to /tmp/task_initial_state.png"

echo "=== boattail_drag_reduction_retrofit task setup complete ==="