#!/bin/bash
# Setup script for Radiochromic Film Dosimetry Calibration task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Dosimetry Calibration Task ==="

# Define paths
DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

# Ensure clean directory structure
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results to prevent gaming
rm -f "$RESULTS_DIR/calibrated_dose_map.tif" 2>/dev/null || true
rm -f "$RESULTS_DIR/dose_report.csv" 2>/dev/null || true
rm -f /tmp/dosimetry_result.json 2>/dev/null || true

# Record task start timestamp (CRITICAL for verification)
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
echo "Found Fiji at: $FIJI_PATH"

# Set display for X11
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Robust launch function
launch_and_verify_fiji() {
    local attempt=$1
    echo "=== Fiji launch attempt $attempt ==="
    pkill -f "fiji\|ImageJ" 2>/dev/null || true
    sleep 2

    # Launch Fiji (no macro needed, user must open sample)
    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &

    # Wait for window
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

    # Wait for GUI stabilization
    sleep 5
    
    # Handle Updater dialog if it appears
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Updater"; then
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    fi
    
    return 0
}

# Try to launch Fiji
if ! launch_and_verify_fiji 1; then
    echo "Retrying launch..."
    if ! launch_and_verify_fiji 2; then
        echo "CRITICAL: Failed to launch Fiji"
        exit 1
    fi
fi

# Maximize window
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="