#!/bin/bash
# Setup script for Shape-Based ROI Filtering task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Shape-Based ROI Filtering Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

# Ensure directories exist and are owned by ga
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results to prevent false positives
rm -f "$RESULTS_DIR/circular_rois.zip" 2>/dev/null || true
rm -f "$RESULTS_DIR/filtered_measurements.csv" 2>/dev/null || true
rm -f /tmp/shape_roi_result.json 2>/dev/null || true

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp
echo "Task start: $(date)"

# ============================================================
# Prepare Fiji
# ============================================================
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

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

# Handle potential updates dialog
sleep 5
if DISPLAY=:1 wmctrl -l | grep -qi "Updater"; then
    DISPLAY=:1 xdotool key Escape
fi

# Focus and maximize
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo "Task: Filter particles by Circularity >= 0.85"
echo "Target: Blobs (25K)"
echo "Outputs:"
echo "  - ~/ImageJ_Data/results/circular_rois.zip"
echo "  - ~/ImageJ_Data/results/filtered_measurements.csv"