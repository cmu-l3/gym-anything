#!/bin/bash
# Setup script for Voronoi Spatial Analysis task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Setting up Voronoi Spatial Analysis task ==="

# Define paths
DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"
RESULT_FILE="$RESULTS_DIR/voronoi_spatial_analysis.csv"

# Ensure directories exist and are owned by user
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR"

# Clean up any previous results
rm -f "$RESULT_FILE" 2>/dev/null || true
rm -f /tmp/voronoi_spatial_analysis_result.json 2>/dev/null || true

# Record task start timestamp (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start time recorded: $(cat /tmp/task_start_timestamp)"

# Kill any existing Fiji/ImageJ instances
echo "Ensuring clean Fiji state..."
kill_fiji 2>/dev/null || true
sleep 2

# Launch Fiji
echo "Launching Fiji..."
launch_fiji
FIJI_PID=$!

# Wait for Fiji to be ready
if wait_for_fiji 60; then
    echo "Fiji launched successfully."
    
    # Get window ID and maximize
    WID=$(get_fiji_window_id)
    if [ -n "$WID" ]; then
        maximize_window "$WID"
        focus_window "$WID"
    fi
else
    echo "ERROR: Fiji failed to launch within timeout."
    exit 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="