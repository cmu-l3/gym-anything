#!/bin/bash
# Setup script for Particle Population Classification task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Particle Classification Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"

# Ensure directories exist and are clean
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clean up previous results to prevent false positives
rm -f "$RESULTS_DIR/small_particles.csv" 2>/dev/null || true
rm -f "$RESULTS_DIR/large_particles.csv" 2>/dev/null || true
rm -f "$RESULTS_DIR/classification_map.png" 2>/dev/null || true
rm -f /tmp/particle_classification_result.json 2>/dev/null || true

# Record task start timestamp for anti-gaming
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

# Launch Fiji
echo "Launching Fiji..."
su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &

# Wait for Fiji window
echo "Waiting for Fiji window..."
wait_for_fiji 60

# Maximize window
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo "Instructions for Agent:"
echo "1. Open 'Blobs (25K)' sample."
echo "2. Filter noise (<60px)."
echo "3. Classify remaining: Small (60-350px), Large (>350px)."
echo "4. Save 'small_particles.csv' and 'large_particles.csv'."
echo "5. Save 'classification_map.png' (Small=Blue, Large=Green)."