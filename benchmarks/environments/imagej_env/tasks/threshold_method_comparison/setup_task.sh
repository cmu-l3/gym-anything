#!/bin/bash
# Setup script for threshold_method_comparison task
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Setting up Threshold Comparison Task ==="

# 1. Prepare directories
DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR"

# 2. Clear previous artifacts
rm -f "$RESULTS_DIR/threshold_comparison.csv" 2>/dev/null || true
rm -f /tmp/threshold_comparison_result.json 2>/dev/null || true

# 3. Record task start timestamp (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Ensure Fiji is running
echo "Ensuring Fiji is running..."
kill_fiji 2>/dev/null || true
sleep 2

# Launch Fiji
launch_fiji
sleep 5

# Wait for Fiji window
wait_for_fiji 60

# 5. Configure UI
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    echo "Fiji window found: $WID"
    focus_window "$WID"
    maximize_window "$WID"
else
    echo "WARNING: Fiji window not found, agent may need to launch it."
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Setup Complete ==="