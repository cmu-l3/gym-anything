#!/bin/bash
# Setup script for Microscopy Time-Lapse Formatting task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Microscopy Time-Lapse Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
PROCESSED_DIR="$DATA_DIR/processed"

mkdir -p "$PROCESSED_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results
rm -f "$PROCESSED_DIR/mitosis_movie_formatted.tif" 2>/dev/null || true
rm -f /tmp/mitosis_task_result.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task start: $(date)"

# Ensure Fiji is not running
kill_fiji
sleep 2

# Launch Fiji
echo "Launching Fiji..."
launch_fiji
sleep 5

# Wait for Fiji window
if wait_for_fiji 60; then
    echo "Fiji started successfully"
    WID=$(get_fiji_window_id)
    if [ -n "$WID" ]; then
        maximize_window "$WID"
        focus_window "$WID"
    fi
else
    echo "ERROR: Fiji failed to start"
    exit 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="