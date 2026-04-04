#!/bin/bash
# Setup script for temporal_change_detection task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Setting up Temporal Change Detection Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

# Ensure directories exist and permissions are correct
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results to ensure clean state
rm -f "$RESULTS_DIR/spindle_start.tif" 2>/dev/null || true
rm -f "$RESULTS_DIR/spindle_end.tif" 2>/dev/null || true
rm -f "$RESULTS_DIR/change_map.tif" 2>/dev/null || true
rm -f "$RESULTS_DIR/change_quantification.csv" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record task start timestamp (critical for anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start: $(date)"

# Kill any existing Fiji instance
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

# Find Fiji executable
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi
echo "Found Fiji at: $FIJI_PATH"

export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch Fiji to ensure it's ready for the user
# We do NOT open the image automatically; the task requires the user to find the sample.
echo "Launching Fiji..."
su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &

# Wait for Fiji window
echo "Waiting for Fiji window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ImageJ\|Fiji"; then
        echo "Fiji window detected"
        break
    fi
    sleep 1
done

# Maximize and focus Fiji
sleep 5
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="