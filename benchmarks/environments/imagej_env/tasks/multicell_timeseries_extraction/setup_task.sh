#!/bin/bash
# Setup script for multicell_timeseries_extraction task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Time-Lapse ROI Profiling Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results
rm -f "$RESULTS_DIR/time_series_traces.csv" 2>/dev/null || true
rm -f "$RESULTS_DIR/cell_rois.zip" 2>/dev/null || true
rm -f /tmp/multicell_timeseries_result.json 2>/dev/null || true

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp
echo "Task start: $(date)"

# Kill any existing Fiji instance
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

# Find and launch Fiji
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi
echo "Found Fiji at: $FIJI_PATH"

export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch Fiji function with retry
launch_and_verify_fiji() {
    local attempt=$1
    echo "=== Fiji launch attempt $attempt ==="
    pkill -f "fiji\|ImageJ" 2>/dev/null || true
    sleep 2

    # Launch without specific macro, just open clean
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
         DISPLAY=:1 xdotool key Escape
    fi
    return 0
}

# Try launching
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

# Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Target: Extract time-series data from 'Mitosis' sample."