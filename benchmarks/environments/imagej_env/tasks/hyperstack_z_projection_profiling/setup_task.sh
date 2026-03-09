#!/bin/bash
# Setup script for Hyperstack Z-Projection task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Hyperstack Z-Projection Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

# Ensure directories exist and have correct permissions
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results to ensure we detect new files
rm -f "$RESULTS_DIR/chromosomes_timelapse.tif" 2>/dev/null || true
rm -f "$RESULTS_DIR/intensity_trace.csv" 2>/dev/null || true
rm -f /tmp/hyperstack_result.json 2>/dev/null || true

# Record task start timestamp (critical for anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start: $(date)"

# ============================================================
# Kill any existing Fiji instance
# ============================================================
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

# ============================================================
# Find Fiji executable
# ============================================================
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi
echo "Found Fiji at: $FIJI_PATH"

export DISPLAY=:1
xhost +local: 2>/dev/null || true

# ============================================================
# Launch Fiji (No image pre-loaded as per description)
# ============================================================
echo "Launching Fiji..."
su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &

# Wait for Fiji window
wait_for_fiji 90

# Maximize and focus Fiji
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
echo "================================================================"
echo "TASK: Hyperstack Z-Projection and Temporal Profiling"
echo "================================================================"
echo "Goal: Create a 2D time-lapse of chromosomes from the Mitosis sample."
echo ""
echo "Steps:"
echo "1. Open 'Mitosis (26MB, 5D stack)'"
echo "2. Create Max Intensity Z-Projection (keep all time frames!)"
echo "3. Split channels to isolate Red channel"
echo "4. Save time-lapse to: ~/ImageJ_Data/results/chromosomes_timelapse.tif"
echo "5. Measure mean intensity over time"
echo "6. Save measurements to: ~/ImageJ_Data/results/intensity_trace.csv"
echo "================================================================"