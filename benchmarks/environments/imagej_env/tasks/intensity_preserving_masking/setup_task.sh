#!/bin/bash
# Setup script for intensity_preserving_masking task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Intensity Preserving Masking Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results
rm -f "$RESULTS_DIR/masked_blobs.tif" 2>/dev/null || true
rm -f /tmp/masking_result.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task start: $(date)"

# Kill any existing Fiji
kill_fiji
sleep 2

# Find and launch Fiji
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi

echo "Launching Fiji..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch Fiji without opening the image (agent must do it)
su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &

# Wait for Fiji window
echo "Waiting for Fiji..."
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ImageJ\|Fiji"; then
        echo "Fiji started."
        break
    fi
    sleep 1
done

sleep 5

# Focus and maximize
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="