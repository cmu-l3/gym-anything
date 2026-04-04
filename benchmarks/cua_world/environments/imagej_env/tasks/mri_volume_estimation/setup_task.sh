#!/bin/bash
set -e
echo "=== Setting up MRI Volume Estimation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_timestamp
echo "Task start time: $(cat /tmp/task_start_timestamp)"

# Ensure results directory exists and is clean
RESULTS_DIR="/home/ga/ImageJ_Data/results"
rm -rf "$RESULTS_DIR"/*
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$RESULTS_DIR"
chown -R ga:ga "/home/ga/ImageJ_Data"

# Clean up any previous run artifacts
rm -f /tmp/mri_volume_estimation_result.json
rm -f /tmp/Results.csv
rm -f /tmp/Summary.csv

# Kill any existing Fiji instances
pkill -f "fiji\|Fiji\|ImageJ" 2>/dev/null || true
sleep 2

# Launch Fiji
echo "Launching Fiji..."
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    # Try one fallback
    FIJI_PATH="/opt/fiji/Fiji.app/ImageJ-linux64"
fi

if [ -n "$FIJI_PATH" ] && [ -x "$FIJI_PATH" ]; then
    export DISPLAY=:1
    xhost +local: 2>/dev/null || true
    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_setup.log 2>&1" &
    FIJI_PID=$!
    echo "Fiji launched with PID: $FIJI_PID"
else
    echo "CRITICAL: Could not find executable Fiji"
    exit 1
fi

# Wait for Fiji main window
echo "Waiting for Fiji to start..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ImageJ\|Fiji"; then
        echo "Fiji window detected after ${i}s"
        break
    fi
    sleep 1
done

# Additional settle time
sleep 5

# Focus and ensure Fiji toolbar is visible
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi

# Dismiss any startup dialogs (Updater, etc.)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== MRI Volume Estimation task setup complete ==="
echo "Instructions:"
echo "1. Open T1 Head MRI sample"
echo "2. Threshold to segment brain"
echo "3. Measure area per slice"
echo "4. Calculate total volume"
echo "5. Save to ~/ImageJ_Data/results/mri_volume_results.csv"