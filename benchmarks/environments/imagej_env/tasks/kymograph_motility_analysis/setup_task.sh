#!/bin/bash
# Setup script for Kymograph Motility Analysis task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Kymograph Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results
rm -f "$RESULTS_DIR/mitosis_kymograph.tif" 2>/dev/null || true
rm -f "$RESULTS_DIR/mitosis_projection.tif" 2>/dev/null || true
rm -f /tmp/kymograph_result.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Fiji is running cleanly
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

# Find Fiji
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi

export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch Fiji
echo "Launching Fiji..."
su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &

# Wait for Fiji window
wait_for_fiji 90

# Focus window
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="