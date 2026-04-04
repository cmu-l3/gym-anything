#!/bin/bash
echo "=== Setting up Aortic Cross-Sectional Area Measurement Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create necessary directories
mkdir -p "$AMOS_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Clean any previous task results
rm -f /tmp/aortic_area_task_result.json 2>/dev/null || true
rm -f "$EXPORTS_DIR/aortic_area_measurement.json" 2>/dev/null || true

# Record initial state
echo "0" > /tmp/initial_export_count
ls -1 "$EXPORTS_DIR"/*.json 2>/dev/null | wc -l > /tmp/initial_export_count || echo "0" > /tmp/initial_export_count

# ============================================================
# Prepare AMOS abdominal CT data
# ============================================================
echo "Preparing AMOS abdominal CT data..."

export CASE_ID AMOS_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_amos_data.sh "$CASE_ID"

# Get the case ID that was actually used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

VOLUME_PATH="$AMOS_DIR/${CASE_ID}.nii.gz"

echo "Using case: $CASE_ID"
echo "Volume path: $VOLUME_PATH"

# Verify volume exists
if [ ! -f "$VOLUME_PATH" ]; then
    echo "ERROR: Volume file not found at $VOLUME_PATH"
    exit 1
fi

echo "Volume file found: $(du -h "$VOLUME_PATH" | cut -f1)"

# Verify ground truth exists
GT_FILE="$GROUND_TRUTH_DIR/${CASE_ID}_aorta_gt.json"
if [ ! -f "$GT_FILE" ]; then
    echo "WARNING: Ground truth not found at $GT_FILE"
else
    echo "Ground truth found"
    # Save ground truth location for verifier
    cp "$GT_FILE" /tmp/aorta_ground_truth.json 2>/dev/null || true
fi

# ============================================================
# Launch 3D Slicer with the volume pre-loaded
# ============================================================
echo "Launching 3D Slicer with abdominal CT data..."

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the volume
export DISPLAY=:1
xhost +local: 2>/dev/null || true

su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$VOLUME_PATH' > /tmp/slicer_launch.log 2>&1 &"

echo "Waiting for 3D Slicer to start..."
sleep 10

# Wait for Slicer window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait additional time for data to load
echo "Waiting for volume to load..."
sleep 10

# Maximize and focus Slicer
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Measure the cross-sectional area of the aorta at maximum diameter level"
echo ""
echo "Input volume: $VOLUME_PATH"
echo "Output JSON: $EXPORTS_DIR/aortic_area_measurement.json"
echo ""
echo "Instructions:"
echo "  1. Navigate through AXIAL slices to find maximum aortic diameter"
echo "  2. Create a Closed Curve markup tracing the aortic lumen boundary"
echo "  3. Record the area and save to the output JSON file"
echo ""
echo "Expected area range: 725-985 mm² (ectatic aorta, ~33mm diameter)"