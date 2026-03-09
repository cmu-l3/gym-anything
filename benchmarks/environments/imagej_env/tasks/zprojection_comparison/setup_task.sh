#!/bin/bash
# Setup script for Z-Projection Comparison task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Setting up Z-Projection Comparison Task ==="

# Define paths
DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

# Ensure directories exist and have correct permissions
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clean up previous results to ensure we are verifying new work
rm -f "$RESULTS_DIR/zprojection_comparison.csv" 2>/dev/null || true
rm -f "$RESULTS_DIR/stddev_projection.tif" 2>/dev/null || true
rm -f /tmp/zprojection_result.json 2>/dev/null || true

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp
echo "Task start: $(date)"

# Ensure clean state by killing any running Fiji instances
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

# Launch Fiji robustly
launch_and_verify_fiji() {
    local attempt=$1
    echo "=== Fiji launch attempt $attempt ==="
    pkill -f "fiji\|ImageJ" 2>/dev/null || true
    sleep 2

    # Launch without any pre-loaded macro/image
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
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 1
    fi

    return 0
}

# Try to launch up to 3 times
FIJI_RUNNING=false
for attempt in 1 2 3; do
    if launch_and_verify_fiji $attempt; then
        FIJI_RUNNING=true
        break
    else
        echo "Attempt $attempt failed, retrying..."
    fi
done

if [ "$FIJI_RUNNING" = false ]; then
    echo "CRITICAL ERROR: Failed to start Fiji"
    exit 1
fi

# Maximize main window
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Task: Z-Projection Statistical Comparison"
echo "1. Open 'MRI Stack' sample."
echo "2. Create Max, Average, Min, Sum, and StdDev projections."
echo "3. Measure statistics (Mean, StdDev, Min, Max) for each."
echo "4. Save stats table to ~/ImageJ_Data/results/zprojection_comparison.csv"
echo "5. Save StdDev projection image to ~/ImageJ_Data/results/stddev_projection.tif"