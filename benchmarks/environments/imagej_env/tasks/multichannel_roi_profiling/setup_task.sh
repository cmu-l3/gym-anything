#!/bin/bash
# Setup script for Multi-Channel ROI Profiling

source /workspace/scripts/task_utils.sh

echo "=== Setting up Multi-Channel ROI Profiling Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results
rm -f "$RESULTS_DIR/nuclei_stack_profiles.csv" 2>/dev/null || true
rm -f /tmp/multichannel_roi_result.json 2>/dev/null || true

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp
echo "Task start: $(date)"

# Kill any existing Fiji instance
kill_fiji
sleep 2

# Find Fiji executable
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi

# Launch Fiji
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Robust launch loop
FIJI_RUNNING=false
for attempt in 1 2 3; do
    # Launch Fiji
    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &
    
    # Wait for window
    if wait_for_fiji 90; then
        FIJI_RUNNING=true
        break
    else
        echo "Attempt $attempt failed, retrying..."
        kill_fiji
        sleep 5
    fi
done

if [ "$FIJI_RUNNING" = false ]; then
    echo "CRITICAL ERROR: Failed to start Fiji"
    exit 1
fi

# Wait for full initialization
sleep 5

# Maximize window
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi

# Dismiss updates if needed
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="