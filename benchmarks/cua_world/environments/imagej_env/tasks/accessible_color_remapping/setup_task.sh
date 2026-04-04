#!/bin/bash
# Setup script for accessible_color_remapping task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Accessible Color Remapping Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"
GT_DIR="/var/lib/imagej"

mkdir -p "$RESULTS_DIR"
mkdir -p "$GT_DIR"
chown -R ga:ga "$DATA_DIR"

# Clear previous results
rm -f "$RESULTS_DIR/accessible_composite.tif" 2>/dev/null || true
rm -f /tmp/remapping_analysis.json 2>/dev/null || true

# Download Ground Truth Image (hidden from agent, used for verification)
# We use the standard ImageJ sample URL
echo "Preparing ground truth data..."
wget -q "https://imagej.net/images/FluorescentCells.jpg" -O "$GT_DIR/ground_truth_cells.jpg"
chmod 644 "$GT_DIR/ground_truth_cells.jpg"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure clean Fiji state
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

# Launch Fiji
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi

echo "Launching Fiji..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &

# Wait for Fiji window
echo "Waiting for Fiji..."
wait_for_fiji 60

# Maximize window
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="