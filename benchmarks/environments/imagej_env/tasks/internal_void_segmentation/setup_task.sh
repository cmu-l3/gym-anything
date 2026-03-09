#!/bin/bash
# Setup script for Internal Void Segmentation task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Internal Void Segmentation Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

# Ensure directories exist and are owned by ga
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR"

# Clean up any previous run artifacts
rm -f "$RESULTS_DIR/void_mask.tif" 2>/dev/null || true
rm -f /tmp/void_segmentation_result.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time
echo "Task start: $(date)"

# Kill any existing Fiji instance to ensure fresh state
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

# Setup display
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Robust Fiji Launch
launch_and_verify_fiji() {
    local attempt=$1
    echo "=== Fiji launch attempt $attempt ==="
    pkill -f "fiji\|ImageJ" 2>/dev/null || true
    sleep 2

    # Launch Fiji (no macro needed, user must open Blobs)
    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &
    
    echo "Waiting for Fiji window..."
    local started=false
    for i in $(seq 1 90); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ImageJ\|Fiji"; then
            echo "Fiji window detected after ${i}s"
            started=true
            break
        fi
        sleep 1
    done

    [ "$started" = false ] && return 1

    sleep 5
    
    # Dismiss Updater if it appears
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Updater"; then
        UPDATER_WID=$(DISPLAY=:1 wmctrl -l | grep -i "Updater" | head -1 | awk '{print $1}')
        [ -n "$UPDATER_WID" ] && DISPLAY=:1 wmctrl -i -a "$UPDATER_WID" 2>/dev/null || true
        sleep 0.5
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
    fi

    local fiji_count=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ImageJ\|Fiji" | grep -v "Updater" | wc -l)
    [ "$fiji_count" -gt 0 ] && return 0 || return 1
}

# Try to launch up to 3 times
FIJI_RUNNING=false
for attempt in 1 2 3; do
    if launch_and_verify_fiji $attempt; then
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

# Maximize Fiji window
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Task: Open Blobs -> Threshold -> Fill Holes -> Image Calculator (Filled - Original) -> Save Result"