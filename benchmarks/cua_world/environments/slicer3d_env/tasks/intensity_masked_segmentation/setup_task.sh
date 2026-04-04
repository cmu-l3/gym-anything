#!/bin/bash
echo "=== Setting up Intensity Masked Segmentation Task ==="

source /workspace/scripts/task_utils.sh

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CASE_ID="amos_0001"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p "$AMOS_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

# Clean previous outputs
rm -f "$EXPORTS_DIR/fat_segmentation.seg.nrrd" 2>/dev/null || true
rm -f "$EXPORTS_DIR/fat_segmentation.nii.gz" 2>/dev/null || true
rm -f /tmp/intensity_mask_result.json 2>/dev/null || true

# Record initial state
echo "0" > /tmp/initial_export_count.txt
ls -1 "$EXPORTS_DIR"/*.nrrd "$EXPORTS_DIR"/*.nii* 2>/dev/null | wc -l > /tmp/initial_export_count.txt || echo "0" > /tmp/initial_export_count.txt

# Prepare AMOS abdominal CT data
echo "Preparing AMOS abdominal CT data..."
export CASE_ID AMOS_DIR GROUND_TRUTH_DIR
/workspace/scripts/prepare_amos_data.sh "$CASE_ID"

# Get case ID used (may differ if download failed and synthetic was used)
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

CT_FILE="$AMOS_DIR/${CASE_ID}.nii.gz"

if [ ! -f "$CT_FILE" ]; then
    echo "ERROR: CT file not found at $CT_FILE"
    exit 1
fi

echo "Using CT file: $CT_FILE"
echo "$CT_FILE" > /tmp/ct_file_path.txt
echo "$CASE_ID" > /tmp/amos_case_id.txt

# Verify ground truth exists for later verification
GT_JSON="$GROUND_TRUTH_DIR/${CASE_ID}_aorta_gt.json"
if [ -f "$GT_JSON" ]; then
    echo "Ground truth file found"
else
    echo "WARNING: No ground truth file (will use heuristic verification)"
fi

# Set permissions
chown -R ga:ga "$AMOS_DIR" 2>/dev/null || true
chown -R ga:ga "$EXPORTS_DIR" 2>/dev/null || true
chmod -R 755 "$EXPORTS_DIR" 2>/dev/null || true

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch 3D Slicer with the CT data
echo "Launching 3D Slicer with abdominal CT..."
export DISPLAY=:1
xhost +local: 2>/dev/null || true

# Launch Slicer with the CT file
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$CT_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
sleep 10

# Wait for window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait additional time for data to load
echo "Waiting for CT data to load..."
sleep 10

# Maximize and focus Slicer
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "CT Data: $CT_FILE"
echo "Output location: $EXPORTS_DIR/fat_segmentation.seg.nrrd"
echo ""
echo "TASK INSTRUCTIONS:"
echo "1. Go to Segment Editor module"
echo "2. Create segment named 'SubcutaneousFat'"
echo "3. Enable 'Editable intensity range' in Masking section"
echo "4. Set intensity range: -150 to -50 HU"
echo "5. Use Paint tool to segment subcutaneous fat"
echo "6. Save segmentation to: ~/Documents/SlicerData/Exports/fat_segmentation.seg.nrrd"
echo ""
echo "NOTE: Intensity masking ensures only fat tissue voxels are included!"