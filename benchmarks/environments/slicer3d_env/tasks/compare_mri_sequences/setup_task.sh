#!/bin/bash
echo "=== Setting up Compare MRI Sequences Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
SCREENSHOTS_DIR="/home/ga/Documents/SlicerData/Screenshots"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Create directories
mkdir -p "$BRATS_DIR"
mkdir -p "$SCREENSHOTS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Record initial screenshot count
INITIAL_SCREENSHOT_COUNT=$(ls -1 "$SCREENSHOTS_DIR"/*.png 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_SCREENSHOT_COUNT" > /tmp/initial_screenshot_count.txt

# Clean any previous task results
rm -f /tmp/mri_compare_result.json 2>/dev/null || true
rm -f "$SCREENSHOTS_DIR/mri_comparison.png" 2>/dev/null || true

# ============================================================
# Prepare BraTS 2021 data
# ============================================================
echo "Preparing BraTS 2021 data..."
/workspace/scripts/prepare_brats_data.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    # Try to find an existing sample
    SAMPLE_ID=$(ls -1 "$BRATS_DIR" 2>/dev/null | grep "BraTS" | head -1 || echo "BraTS2021_00000")
fi

echo "Using BraTS sample: $SAMPLE_ID"
echo "$SAMPLE_ID" > /tmp/current_sample_id.txt

# Verify data files exist
CASE_DIR="$BRATS_DIR/$SAMPLE_ID"
REQUIRED_FILES=("${SAMPLE_ID}_t1.nii.gz" "${SAMPLE_ID}_t1ce.nii.gz" "${SAMPLE_ID}_t2.nii.gz" "${SAMPLE_ID}_flair.nii.gz")

echo "Checking for required files in $CASE_DIR..."
MISSING_FILES=0
for f in "${REQUIRED_FILES[@]}"; do
    if [ -f "$CASE_DIR/$f" ]; then
        echo "  Found: $f ($(du -h "$CASE_DIR/$f" 2>/dev/null | cut -f1))"
    else
        echo "  MISSING: $f"
        MISSING_FILES=$((MISSING_FILES + 1))
    fi
done

if [ "$MISSING_FILES" -gt 0 ]; then
    echo "ERROR: $MISSING_FILES required files missing!"
    echo "Data preparation may have failed."
    # Try one more time
    /workspace/scripts/prepare_brats_data.sh
    SAMPLE_ID=$(cat /tmp/brats_sample_id 2>/dev/null || echo "$SAMPLE_ID")
fi

# ============================================================
# Record ground truth info for verification
# ============================================================
python3 << PYEOF
import os
import json

sample_id = "$SAMPLE_ID"
case_dir = "$CASE_DIR"
gt_dir = "$GROUND_TRUTH_DIR"

gt_info = {
    "sample_id": sample_id,
    "case_dir": case_dir,
    "expected_volumes": 4,
    "expected_sequences": ["t1", "t1ce", "t2", "flair"],
    "files_present": {}
}

for seq in ["t1", "t1ce", "t2", "flair"]:
    fpath = os.path.join(case_dir, f"{sample_id}_{seq}.nii.gz")
    gt_info["files_present"][seq] = os.path.exists(fpath)

# Try to get dimensions
try:
    import nibabel as nib
    t1_path = os.path.join(case_dir, f"{sample_id}_t1.nii.gz")
    if os.path.exists(t1_path):
        nii = nib.load(t1_path)
        gt_info["dimensions"] = list(nii.shape[:3])
except Exception as e:
    gt_info["dimensions"] = [240, 240, 155]  # Default BraTS dimensions
    gt_info["dimension_error"] = str(e)

# Save ground truth
gt_path = os.path.join(gt_dir, "mri_compare_gt.json")
with open(gt_path, "w") as f:
    json.dump(gt_info, f, indent=2)

print(f"Ground truth saved to {gt_path}")
print(json.dumps(gt_info, indent=2))
PYEOF

# Set permissions
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true
chown -R ga:ga "$BRATS_DIR" 2>/dev/null || true
chown -R ga:ga "$SCREENSHOTS_DIR" 2>/dev/null || true

# ============================================================
# Launch 3D Slicer (empty scene)
# ============================================================
echo ""
echo "Launching 3D Slicer..."

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer without any data loaded (agent must load it)
sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash > /tmp/slicer_launch.log 2>&1 &

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
wait_for_slicer 90

# Maximize and focus window
sleep 3
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "BraTS data location: $CASE_DIR"
echo "Sample ID: $SAMPLE_ID"
echo "Screenshot output: $SCREENSHOTS_DIR/mri_comparison.png"
echo ""
echo "Files to load:"
for f in "${REQUIRED_FILES[@]}"; do
    echo "  - $CASE_DIR/$f"
done
echo ""
echo "TASK: Load all 4 MRI sequences, set up a multi-panel comparison layout,"
echo "      and save a screenshot showing all sequences side-by-side."