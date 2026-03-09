#!/bin/bash
# Setup script for stack_reslicing_analysis task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Stack Reslicing Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results
rm -f "$RESULTS_DIR/side_view_projection.tif" 2>/dev/null || true
rm -f /tmp/stack_reslicing_result.json 2>/dev/null || true

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp
echo "Task start: $(date)"

# Ensure clean Fiji state
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

# Robust Fiji launch function
launch_and_verify_fiji() {
    local attempt=$1
    echo "=== Fiji launch attempt $attempt ==="
    pkill -f "fiji\|ImageJ" 2>/dev/null || true
    sleep 2

    # Launch without specific macro, just base Fiji
    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &
    
    echo "Waiting for Fiji window..."
    local started=false
    for i in $(seq 1 60); do
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
    
    return 0
}

# Try to launch
if ! launch_and_verify_fiji 1; then
    launch_and_verify_fiji 2
fi

# Maximize and focus
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Task: Orthogonal Reslicing and Projection"
echo "Target: Open 'Fly Brain', Reslice (Top), Z-Project (Max), Save as 'side_view_projection.tif'"