#!/bin/bash
# Setup script for zstack_depth_profiling task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Z-Stack Profiling Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results
rm -f "$RESULTS_DIR/fly_brain_MIP.tif"
rm -f "$RESULTS_DIR/fly_brain_AVG.tif"
rm -f "$RESULTS_DIR/fly_brain_reslice_XZ.tif"
rm -f "$RESULTS_DIR/fly_brain_montage.tif"
rm -f "$RESULTS_DIR/fly_brain_z_profile.csv"
rm -f /tmp/zstack_result.json

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

export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch Fiji
launch_and_verify_fiji() {
    local attempt=$1
    echo "=== Fiji launch attempt $attempt ==="
    pkill -f "fiji\|ImageJ" 2>/dev/null || true
    sleep 2

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
    
    # Dismiss updater if needed
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Updater"; then
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    fi

    local fiji_count=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ImageJ\|Fiji" | grep -v "Updater" | wc -l)
    [ "$fiji_count" -gt 0 ] && return 0 || return 1
}

if ! launch_and_verify_fiji 1; then
    launch_and_verify_fiji 2 || echo "WARNING: Fiji might not have started correctly"
fi

WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi
sleep 2

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="