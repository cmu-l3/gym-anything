#!/bin/bash
# Setup script for Boolean Overlap Analysis task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Boolean Overlap Analysis Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

# Ensure directories exist and have correct permissions
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results to prevent gaming
rm -f "$RESULTS_DIR/mask_red.tif"
rm -f "$RESULTS_DIR/mask_green.tif"
rm -f "$RESULTS_DIR/mask_overlap.tif"
rm -f "$RESULTS_DIR/overlap_counts.csv"
rm -f /tmp/boolean_overlap_result.json

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp
echo "Task start: $(date)"

# Kill any existing Fiji instance to ensure clean state
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