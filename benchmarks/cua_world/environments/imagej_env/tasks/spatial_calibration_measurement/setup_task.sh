#!/bin/bash
# Setup script for spatial_calibration_measurement task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Setting up Spatial Calibration Task ==="

# Define directories
DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

# Ensure directories exist and have correct permissions
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR"

# Clear any previous results
rm -f "$RESULTS_DIR/calibrated_blob_measurements.csv" 2>/dev/null || true
rm -f /tmp/spatial_calibration_result.json 2>/dev/null || true

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp
echo "Task start: $(date)"

# Ensure Fiji is running and clean
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

# Find Fiji executable
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi

# Launch Fiji
echo "Launching Fiji..."
export DISPLAY=:1
su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &

# Wait for Fiji window
if wait_for_fiji 60; then
    echo "Fiji launched successfully."
    WID=$(get_fiji_window_id)
    if [ -n "$WID" ]; then
        maximize_window "$WID"
        focus_window "$WID"
    fi
else
    echo "ERROR: Fiji failed to launch."
    exit 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="