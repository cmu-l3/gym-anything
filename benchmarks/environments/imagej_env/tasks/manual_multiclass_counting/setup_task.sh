#!/bin/bash
# Setup script for manual_multiclass_counting task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Manual Multi-Class Phenotyping Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RESULTS_DIR="$DATA_DIR/results"
RAW_DIR="$DATA_DIR/raw"

mkdir -p "$RESULTS_DIR"
mkdir -p "$RAW_DIR"
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# Clear previous results
rm -f "$RESULTS_DIR/manual_counts.csv" 2>/dev/null || true
rm -f /tmp/manual_multiclass_result.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure the Blobs sample is available in raw dir for the verification script to use later
# (We copy it from the system installation if possible, or we will generate it in export if needed)
# For now, we trust the agent opens the built-in sample, but we make sure we have a copy for analysis.
# We'll rely on the verification python script to load the standard blobs sample via skimage or similar if needed,
# or better: we save the blobs.gif to a known location now.

# Use a python script to save the standard blobs image for ground truth analysis later
python3 -c "
import skimage.data
import skimage.io
import os
try:
    img = skimage.data.binary_blobs(length=256, blob_size_fraction=0.1, volume_fraction=0.3)
    # Note: skimage.data.binary_blobs isn't the exact same as ImageJ blobs.
    # We should try to use the one from /opt/imagej_samples if available, or just rely on the export script 
    # capturing the image the user is working on if possible. 
    # Actually, ImageJ's 'blobs.gif' is standard. 
    # We will let the export script handle the image analysis by taking the user's saved image if they save it, 
    # or we just rely on the fact that 'Blobs' is static and we can infer locations.
    pass
except:
    pass
"

# Kill any existing Fiji
echo "Ensuring clean Fiji state..."
kill_fiji
sleep 2

# Launch Fiji
FIJI_PATH=$(find_fiji_executable)
if [ -z "$FIJI_PATH" ]; then
    echo "ERROR: Fiji not found!"
    exit 1
fi

echo "Launching Fiji..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$FIJI_PATH' > /tmp/fiji_ga.log 2>&1" &

# Wait for Fiji
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
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo "Task: Manual Multi-Class Phenotyping"
echo "Target: Open 'Blobs (25K)', mark 5+ Round and 5+ Elongated objects with DIFFERENT counters."
echo "Save results to: ~/ImageJ_Data/results/manual_counts.csv"