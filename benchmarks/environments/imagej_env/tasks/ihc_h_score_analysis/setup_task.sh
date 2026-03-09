#!/bin/bash
# Setup script for IHC H-Score Analysis
# Launches Fiji and ensures clean state

source /workspace/scripts/task_utils.sh

echo "=== Setting up IHC H-Score Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results
rm -f "$RESULTS_DIR/h_score_report.csv" 2>/dev/null || true
rm -f /tmp/h_score_result.json 2>/dev/null || true
rm -f /tmp/ground_truth_metrics.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# ============================================================
# Launch Fiji
# ============================================================
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi

export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch Fiji
su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &

# Wait for Fiji window
wait_for_fiji 60

# Maximize window
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Task: Calculate Area-based H-Score for Red Channel of Fluorescent Cells"