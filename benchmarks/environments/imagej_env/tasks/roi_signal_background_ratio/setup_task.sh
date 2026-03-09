#!/bin/bash
# Setup script for ROI Signal-to-Background Ratio task

source /workspace/scripts/task_utils.sh

echo "=== Setting up ROI SBR Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

# Ensure directories exist and are clean
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR"

# Clear previous results to ensure we verify new work
rm -f "$RESULTS_DIR/roi_measurements.csv" 2>/dev/null || true
rm -f "$RESULTS_DIR/roi_set.zip" 2>/dev/null || true
rm -f /tmp/roi_sbr_result.json 2>/dev/null || true

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp
echo "Task start time recorded: $(cat /tmp/task_start_timestamp)"

# Kill any existing Fiji instance
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

# Find Fiji
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi

# Launch Fiji (Standard launch, no image pre-opened as per description)
echo "Launching Fiji..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &

# Wait for Fiji window
if wait_for_fiji 60; then
    echo "Fiji launched successfully"
    WID=$(get_fiji_window_id)
    if [ -n "$WID" ]; then
        maximize_window "$WID"
        focus_window "$WID"
    fi
else
    echo "ERROR: Fiji failed to launch"
    exit 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Task: Multi-ROI Fluorescence Signal-to-Background Ratio"
echo "Instructions:"
echo "1. Open 'Fluorescent Cells' sample"
echo "2. Define ROIs (Signal, Cytoplasm, Background) with specific names"
echo "3. Measure Mean Intensities"
echo "4. Calculate Signal-to-Background Ratio"
echo "5. Save measurements.csv and roi_set.zip to ~/ImageJ_Data/results/"