#!/bin/bash
# Setup script for river_morphometry task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Setting up River Morphometry Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results
rm -f "$RESULTS_DIR/river_morphometry.csv" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record task start timestamp (critical for anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start: $(date)"

# ============================================================
# Ensure clean state
# ============================================================
echo "Ensuring clean Fiji state..."
kill_fiji 2>/dev/null || true
sleep 2

# ============================================================
# Launch Fiji
# ============================================================
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi

echo "Launching Fiji..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Robust launch function
launch_fiji_robust() {
    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ImageJ\|Fiji"; then
            echo "Fiji started"
            return 0
        fi
        sleep 1
    done
    return 1
}

if ! launch_fiji_robust; then
    echo "Failed to start Fiji"
    exit 1
fi

# Maximize and focus
sleep 5
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
    
    # Dismiss updater if present
    sleep 2
    if DISPLAY=:1 wmctrl -l | grep -qi "Updater"; then
        DISPLAY=:1 xdotool key Escape
    fi
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="