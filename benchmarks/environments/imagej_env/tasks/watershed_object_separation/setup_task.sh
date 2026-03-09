#!/bin/bash
# Setup script for Watershed Segmentation task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Watershed Segmentation Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results to prevent gaming
rm -f "$RESULTS_DIR/watershed_measurements.csv" 2>/dev/null || true
rm -f "$RESULTS_DIR/watershed_summary.txt" 2>/dev/null || true
rm -f /tmp/watershed_result.json 2>/dev/null || true

# Record task start timestamp (critical for anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start: $(date)"

# ============================================================
# Prepare Fiji
# ============================================================
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi
echo "Found Fiji at: $FIJI_PATH"

export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Function to launch and verify Fiji
launch_and_verify_fiji() {
    local attempt=$1
    echo "=== Fiji launch attempt $attempt ==="
    pkill -f "fiji\|ImageJ" 2>/dev/null || true
    sleep 2

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
    
    # Wait for GUI initialization
    sleep 5
    
    # Dismiss updater if needed
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Updater"; then
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    fi
    
    return 0
}

# Launch Fiji
if ! launch_and_verify_fiji 1; then
    echo "Retry launching Fiji..."
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

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Task: Watershed Segmentation and Object Separation"
echo "1. Open Blobs (25K) sample."
echo "2. Threshold to binary."
echo "3. Count objects BEFORE watershed."
echo "4. Apply Watershed."
echo "5. Count objects AFTER watershed."
echo "6. Save measurements to ~/ImageJ_Data/results/watershed_measurements.csv"
echo "7. Save summary counts to ~/ImageJ_Data/results/watershed_summary.txt"