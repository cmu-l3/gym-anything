#!/bin/bash
# Setup script for CLAHE Enhancement Comparison task

source /workspace/scripts/task_utils.sh

echo "=== Setting up CLAHE Comparison Task ==="

# Define paths
DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

# Ensure directories exist and are owned by ga
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR"

# Clear previous results to prevent gaming
rm -f "$RESULTS_DIR/clahe_comparison.png" 2>/dev/null || true
rm -f /tmp/clahe_task_result.json 2>/dev/null || true

# Record task start timestamp (CRITICAL for anti-gaming)
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

# Set display
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Function to launch Fiji
launch_fiji_safe() {
    echo "Launching Fiji..."
    su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ImageJ\|Fiji"; then
            echo "Fiji window detected."
            return 0
        fi
        sleep 1
    done
    return 1
}

# Launch Fiji
if ! launch_fiji_safe; then
    echo "Failed to launch Fiji"
    exit 1
fi

# Maximize window
sleep 5
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Task: Create CLAHE comparison montage."
echo "Output expected: $RESULTS_DIR/clahe_comparison.png"