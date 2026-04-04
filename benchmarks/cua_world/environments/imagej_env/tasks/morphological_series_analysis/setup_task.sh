#!/bin/bash
# Setup script for Morphological Series Analysis task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Setting up Morphological Series Analysis Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results
rm -f "$RESULTS_DIR/morphological_series.csv" 2>/dev/null || true
rm -f /tmp/morphological_series_analysis_result.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task start: $(date)"

# Kill any existing Fiji instance
echo "Ensuring clean Fiji state..."
kill_fiji 2>/dev/null || true
sleep 2

# Find Fiji executable
FIJI_PATH=$(find_fiji_executable 2>/dev/null)
if [ -z "$FIJI_PATH" ]; then
    # Fallback search if helper fails
    FIJI_PATH=$(find /opt/fiji -name "ImageJ-linux64" -o -name "fiji-linux64" | head -1)
fi

if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi
echo "Found Fiji at: $FIJI_PATH"

export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch Fiji
echo "Launching Fiji..."
su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &

# Wait for Fiji window
echo "Waiting for Fiji window..."
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ImageJ\|Fiji"; then
        echo "Fiji window detected after ${i}s"
        break
    fi
    sleep 1
done

# Wait for initialization
sleep 5

# Maximize Fiji window
WID=$(get_fiji_window_id 2>/dev/null)
if [ -n "$WID" ]; then
    maximize_window "$WID" 2>/dev/null || true
    focus_window "$WID" 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="