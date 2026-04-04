#!/bin/bash
# Setup script for manual_mitosis_tracking task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Manual Mitosis Tracking Task ==="

# Define paths
DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR"

# Clean up previous results
rm -f "$RESULTS_DIR/tracking_trace.csv" 2>/dev/null || true
rm -f /tmp/mitosis_task_result.json 2>/dev/null || true

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time
echo "Task start: $(date)"

# Ensure clean state by killing existing Fiji instances
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

# Find Fiji executable
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi

# Launch Fiji (Standard Launch)
echo "Launching Fiji..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Use standard launch logic from utils
launch_fiji
sleep 15  # Wait for splash screen and load

# Verify launch
WID=$(get_fiji_window_id)
if [ -z "$WID" ]; then
    echo "WARNING: Fiji window not detected initially, waiting..."
    sleep 10
    WID=$(get_fiji_window_id)
fi

if [ -n "$WID" ]; then
    echo "Fiji launched successfully (WID: $WID)"
    maximize_window "$WID"
    focus_window "$WID"
else
    echo "ERROR: Failed to launch Fiji"
    exit 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo "Task: Track the dividing cell near (145, 130) in the 'Mitosis' sample."
echo "1. Open 'Mitosis' (File > Open Samples > Mitosis)"
echo "2. Z-Project (Max Intensity)"
echo "3. Record X,Y coordinates for Frames 1, 6, 11, 16, 21"
echo "4. Save to ~/ImageJ_Data/results/tracking_trace.csv"