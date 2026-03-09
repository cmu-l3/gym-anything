#!/bin/bash
# Setup script for segmentation_validation_ground_truth task

source /workspace/scripts/task_utils.sh

echo "=== Setting up Segmentation Validation Task ==="

DATA_DIR="/home/ga/ImageJ_Data"
RAW_DIR="$DATA_DIR/raw/BBBC005"
GT_DIR="$DATA_DIR/raw/BBBC005_ground_truth"
RESULTS_DIR="$DATA_DIR/results"

# Ensure directories exist
mkdir -p "$RAW_DIR"
mkdir -p "$GT_DIR"
mkdir -p "$RESULTS_DIR"

# Source locations (from install_imagej.sh)
SOURCE_BBBC="/opt/imagej_samples/BBBC005"
SOURCE_GT="/opt/imagej_samples/BBBC005_ground_truth"

# Copy specific test files if they exist in /opt, otherwise we rely on what's there
# We need to ensure the specific file mentioned in description is available
TARGET_FILE="SIMCEPImages_A01_C1_F1_s01_w1.TIF"

echo "Preparing data files..."
if [ -d "$SOURCE_BBBC" ]; then
    cp "$SOURCE_BBBC/$TARGET_FILE" "$RAW_DIR/" 2>/dev/null || \
    cp $(find "$SOURCE_BBBC" -name "*.TIF" | head -1) "$RAW_DIR/$TARGET_FILE"
fi

if [ -d "$SOURCE_GT" ]; then
    cp "$SOURCE_GT/$TARGET_FILE" "$GT_DIR/" 2>/dev/null || \
    cp $(find "$SOURCE_GT" -name "*.TIF" | head -1) "$GT_DIR/$TARGET_FILE"
fi

# Set permissions
chown -R ga:ga "$DATA_DIR"

# Clear previous results
rm -f "$RESULTS_DIR/segmentation_difference.tif" 2>/dev/null || true
rm -f "$RESULTS_DIR/validation_metrics.csv" 2>/dev/null || true
rm -f /tmp/validation_result.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Fiji is not running
kill_fiji
sleep 2

# Launch Fiji
echo "Launching Fiji..."
launch_fiji
sleep 5

# Wait for Fiji
wait_for_fiji 60

# Maximize
WID=$(get_fiji_window_id)
if [ -n "$WID" ]; then
    maximize_window "$WID"
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="