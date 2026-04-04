#!/bin/bash
# Setup script for Z-Axis Nuclear Depth task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Z-Axis Nuclear Depth Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RAW_DIR="$DATA_DIR/raw"
RESULTS_DIR="$DATA_DIR/results"
SOURCE_STACK="/opt/imagej_samples/HeLa_stack"

mkdir -p "$RAW_DIR"
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR"

# Clear previous results
rm -f "$RESULTS_DIR/nucleus_depth.csv" 2>/dev/null || true
rm -f "$RESULTS_DIR/nucleus_reslice.tif" 2>/dev/null || true
rm -f /tmp/z_axis_result.json 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time

# Prepare Data
# Ensure the HeLa stack is in the user's raw directory
if [ -d "$SOURCE_STACK" ]; then
    echo "Copying HeLa stack to user directory..."
    rm -rf "$RAW_DIR/HeLa_stack"
    cp -r "$SOURCE_STACK" "$RAW_DIR/"
    chown -R ga:ga "$RAW_DIR/HeLa_stack"
else
    echo "WARNING: Source stack not found at $SOURCE_STACK"
    # Fallback: Create a dummy stack if real data missing (should not happen in prod)
    mkdir -p "$RAW_DIR/HeLa_stack"
    # We rely on the environment having installed the samples
fi

# Kill any existing Fiji instance
kill_fiji
sleep 2

# Launch Fiji (clean state)
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi

echo "Launching Fiji..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch without opening image (agent must open it)
su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &

# Wait for Fiji
if wait_for_fiji 60; then
    echo "Fiji launched successfully"
    WID=$(get_fiji_window_id)
    if [ -n "$WID" ]; then
        maximize_window "$WID"
        focus_window "$WID"
    fi
else
    echo "ERROR: Fiji failed to launch"
    exit 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="