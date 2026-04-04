#!/bin/bash
echo "=== Setting up Clip 3D Rendering Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_SCREENSHOT="$SCREENSHOT_DIR/clipped_brain_rendering.png"

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create directories
mkdir -p "$BRATS_DIR"
mkdir -p "$SCREENSHOT_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Clean previous results
rm -f /tmp/clip_task_result.json 2>/dev/null || true
rm -f "$OUTPUT_SCREENSHOT" 2>/dev/null || true

# Record initial state - check if output exists
INITIAL_SCREENSHOT_EXISTS="false"
if [ -f "$OUTPUT_SCREENSHOT" ]; then
    INITIAL_SCREENSHOT_EXISTS="true"
    INITIAL_SCREENSHOT_MTIME=$(stat -c%Y "$OUTPUT_SCREENSHOT" 2>/dev/null || echo "0")
else
    INITIAL_SCREENSHOT_MTIME="0"
fi

cat > /tmp/initial_state.json << EOF
{
    "screenshot_exists": $INITIAL_SCREENSHOT_EXISTS,
    "screenshot_mtime": $INITIAL_SCREENSHOT_MTIME,
    "task_start_time": $(cat /tmp/task_start_time.txt)
}
EOF

echo "Initial state recorded"

# ============================================================
# Prepare BraTS data (download if needed)
# ============================================================
echo "Preparing BraTS data..."
/workspace/scripts/prepare_brats_data.sh 2>&1 | tee /tmp/brats_prep.log

# Get the sample ID used
SAMPLE_ID="BraTS2021_00000"
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
fi

echo "Using BraTS sample: $SAMPLE_ID"

# Find the T1ce file
T1CE_FILE=""
for dir in "$BRATS_DIR/$SAMPLE_ID" "$BRATS_DIR"; do
    for pattern in "${SAMPLE_ID}_t1ce.nii.gz" "*_t1ce.nii.gz"; do
        found=$(find "$dir" -maxdepth 2 -name "$pattern" 2>/dev/null | head -1)
        if [ -n "$found" ] && [ -f "$found" ]; then
            T1CE_FILE="$found"
            break 2
        fi
    done
done

if [ -z "$T1CE_FILE" ] || [ ! -f "$T1CE_FILE" ]; then
    echo "ERROR: T1ce file not found in $BRATS_DIR"
    echo "Available files:"
    find "$BRATS_DIR" -name "*.nii.gz" -type f 2>/dev/null | head -20
    exit 1
fi

echo "T1ce file found: $T1CE_FILE"

# Save paths for export script
echo "$SAMPLE_ID" > /tmp/brats_sample_id
echo "$T1CE_FILE" > /tmp/t1ce_path.txt

# Set permissions
chown -R ga:ga "$BRATS_DIR" 2>/dev/null || true
chown -R ga:ga "$SCREENSHOT_DIR" 2>/dev/null || true

# ============================================================
# Launch 3D Slicer (empty scene - agent will load data)
# ============================================================
echo "Launching 3D Slicer..."

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer as ga user
export DISPLAY=:1
xhost +local: 2>/dev/null || true

su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_launch.log 2>&1 &"

echo "Waiting for 3D Slicer to start..."
sleep 10

# Wait for Slicer window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait additional time for Slicer to fully load modules
echo "Waiting for Slicer to fully initialize..."
sleep 15

# Maximize and focus Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c%s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: $SIZE bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "BraTS Sample: $SAMPLE_ID"
echo "T1ce File: $T1CE_FILE"
echo "Output Screenshot: $OUTPUT_SCREENSHOT"
echo ""
echo "TASK INSTRUCTIONS:"
echo "1. Load the T1ce brain MRI from: $T1CE_FILE"
echo "2. Enable Volume Rendering (Modules > Volume Rendering)"
echo "3. Enable Display ROI and Crop checkboxes"
echo "4. Adjust ROI to clip away part of the brain surface"
echo "5. Save screenshot to: $OUTPUT_SCREENSHOT"
echo ""