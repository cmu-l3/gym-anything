#!/bin/bash
echo "=== Setting up Compute Segmentation Quality Metrics Task ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
AI_SEG_PATH="$BRATS_DIR/ai_segmentation.nii.gz"
OUTPUT_REPORT="$EXPORTS_DIR/segmentation_metrics.json"

# Create directories
mkdir -p "$BRATS_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
mkdir -p "$EXPORTS_DIR"
chown -R ga:ga /home/ga/Documents/SlicerData

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clean previous task results
rm -f /tmp/segmentation_metrics_result.json 2>/dev/null || true
rm -f "$OUTPUT_REPORT" 2>/dev/null || true
rm -f /tmp/task_initial.png 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# Record initial state
echo "Recording initial state..."
ls -la "$EXPORTS_DIR"/*.json 2>/dev/null > /tmp/initial_exports_list.txt || echo "none" > /tmp/initial_exports_list.txt

# ============================================================
# Step 1: Prepare BraTS data (downloads if needed)
# ============================================================
echo "Preparing BraTS data..."
/workspace/scripts/prepare_brats_data.sh "BraTS2021_00000"

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

echo "Using BraTS sample: $SAMPLE_ID"

# Verify ground truth segmentation exists
GT_SEG="$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"
if [ ! -f "$GT_SEG" ]; then
    echo "ERROR: Ground truth segmentation not found at $GT_SEG"
    exit 1
fi
echo "Ground truth segmentation: $GT_SEG"

# ============================================================
# Step 2: Create the broken (AI) segmentation
# ============================================================
echo "Creating AI segmentation with deliberate errors..."

export BRATS_DIR GROUND_TRUTH_DIR SAMPLE_ID
export GT_SEG="$GT_SEG"
export OUTPUT_BROKEN="$AI_SEG_PATH"

/workspace/scripts/create_broken_segmentation.sh

# Verify AI segmentation was created
if [ ! -f "$AI_SEG_PATH" ]; then
    echo "ERROR: AI segmentation not created at $AI_SEG_PATH"
    exit 1
fi
echo "AI segmentation created: $AI_SEG_PATH ($(du -h "$AI_SEG_PATH" | cut -f1))"

# ============================================================
# Step 3: Store expected metrics for verification
# ============================================================
echo "Storing expected metrics for verification..."

# The broken_errors.json contains the pre-computed Dice
ERRORS_JSON="$GROUND_TRUTH_DIR/${SAMPLE_ID}_broken_errors.json"
if [ -f "$ERRORS_JSON" ]; then
    # Extract expected Dice from the errors file
    EXPECTED_DICE=$(python3 -c "
import json
with open('$ERRORS_JSON') as f:
    data = json.load(f)
metrics = data.get('quality_metrics', {})
print(metrics.get('dice_before_correction', 0.80))
" 2>/dev/null || echo "0.80")
    echo "Expected Dice coefficient: $EXPECTED_DICE"
else
    EXPECTED_DICE="0.80"
fi

# Save expected values for verifier
cat > /tmp/expected_metrics.json << EOF
{
    "sample_id": "$SAMPLE_ID",
    "ai_segmentation_path": "$AI_SEG_PATH",
    "reference_segmentation_path": "$GT_SEG",
    "expected_dice_approx": $EXPECTED_DICE,
    "expected_dice_min": 0.70,
    "expected_dice_max": 0.90,
    "expected_hausdorff_min_mm": 5,
    "expected_hausdorff_max_mm": 35
}
EOF
chmod 644 /tmp/expected_metrics.json

# ============================================================
# Step 4: Launch 3D Slicer
# ============================================================
echo "Launching 3D Slicer..."

# Kill any existing Slicer instances
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start
echo "Waiting for 3D Slicer to start..."
wait_for_slicer 90

# Maximize and focus
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial screenshot..."
take_screenshot /tmp/task_initial.png ga

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Compute segmentation quality metrics"
echo ""
echo "Files to load:"
echo "  AI segmentation:        $AI_SEG_PATH"
echo "  Reference segmentation: $GT_SEG"
echo ""
echo "Output file:"
echo "  $OUTPUT_REPORT"
echo ""
echo "Steps:"
echo "  1. Load both segmentation files (import as Segmentation, not volume)"
echo "  2. Open Segment Comparison module (Modules > Quantification > Segment Comparison)"
echo "  3. Select AI seg as 'Compare' and reference as 'Reference'"
echo "  4. Click Apply to compute metrics"
echo "  5. Export results to JSON"
echo ""
echo "=== Ready for agent ==="