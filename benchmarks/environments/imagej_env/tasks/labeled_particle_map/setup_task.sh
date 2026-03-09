#!/bin/bash
# Setup script for labeled_particle_map task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Indexed Particle Map Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results
rm -f "$RESULTS_DIR/labeled_map.png" 2>/dev/null || true
rm -f "$RESULTS_DIR/particle_data.csv" 2>/dev/null || true
rm -f /tmp/labeled_map_result.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure clean Fiji state
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

# Find Fiji
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi

# Launch Fiji
export DISPLAY=:1
xhost +local: 2>/dev/null || true

echo "Launching Fiji..."
su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx2g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &

# Wait for Fiji window
wait_for_fiji 60

# Maximize
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi
sleep 2

# Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="