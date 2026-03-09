#!/bin/bash
# Setup script for Tree Ring Measurement task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Tree Ring Measurement Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

# Ensure directories exist and are clean
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR"

# Remove any previous results
rm -f "$RESULTS_DIR/tree_ring_measurements.csv" 2>/dev/null || true
rm -f /tmp/tree_ring_measurement_result.json 2>/dev/null || true

# Record task start timestamp (critical for anti-gaming)
date +%s > /tmp/task_start_time
echo "Task start: $(date)"

# Kill any existing Fiji instance to ensure clean state
kill_fiji
sleep 2

# Find Fiji
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi
echo "Found Fiji at: $FIJI_PATH"

export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch Fiji (Standard launch, NO image pre-loaded - agent must open it)
echo "Launching Fiji..."
su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &

# Wait for Fiji window
echo "Waiting for Fiji window..."
wait_for_fiji 90

# Ensure window is ready
sleep 5
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi

# Dismiss any updater dialogs
sleep 2
if DISPLAY=:1 wmctrl -l | grep -qi "Updater"; then
    DISPLAY=:1 xdotool key Escape
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Goal: Measure >5 tree rings from 'Tree Rings' sample and save to ~/ImageJ_Data/results/tree_ring_measurements.csv"