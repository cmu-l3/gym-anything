#!/bin/bash
# Setup script for MRI Stack Formatting task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Setting up MRI Stack Formatting Task ==="

# Define paths
DATA_DIR="/home/ga/ImageJ_Data"
PROCESSED_DIR="$DATA_DIR/processed"
OUTPUT_FILE="$PROCESSED_DIR/mri_preview.tif"

# Create directories
mkdir -p "$PROCESSED_DIR"
chown -R ga:ga "$DATA_DIR"

# Clear previous output to prevent false positives
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing previous output file..."
    rm -f "$OUTPUT_FILE"
fi

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time
echo "Task start time recorded: $(cat /tmp/task_start_time)"

# Kill any existing Fiji instances to ensure a clean start
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

# Find Fiji executable
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi

# Launch Fiji
echo "Launching Fiji..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch in background
su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_launch.log 2>&1" &

# Wait for Fiji window
echo "Waiting for Fiji to start..."
wait_for_fiji 60

# Maximize window
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    echo "Maximizing Fiji window ($WID)..."
    maximize_window "$WID"
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Instructions:"
echo "1. Open T1 Head (File > Open Samples)"
echo "2. Convert to 8-bit"
echo "3. Scale to 75%"
echo "4. Substack (every 3rd slice)"
echo "5. Save to $OUTPUT_FILE"