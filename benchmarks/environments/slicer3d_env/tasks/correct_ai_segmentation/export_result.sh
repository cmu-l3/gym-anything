#!/bin/bash
echo "=== Exporting Correct AI Segmentation Result ==="

source /workspace/scripts/task_utils.sh

# Get task identifiers
SAMPLE_ID=$(cat /tmp/task_sample_id.txt 2>/dev/null || echo "BraTS2021_00000")
BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
CORRECTED_PATH="$BRATS_DIR/corrected_segmentation.nii.gz"
AI_SEG_PATH="$BRATS_DIR/ai_segmentation.nii.gz"
GT_SEG_PATH="$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export segmentation from Slicer
    echo "Attempting to export segmentation from Slicer..."
    cat > /tmp/export_corrected_seg.py << 'PYEOF'
import slicer
import os

brats_dir = "/home/ga/Documents/SlicerData/BraTS"
output_path = os.path.join(brats_dir, "corrected_segmentation.nii.gz")

# Find segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

saved = False
for seg_node in seg_nodes:
    name = seg_node.GetName()
    print(f"  Checking segmentation: {name}")
    
    # Skip if it's clearly the original AI segmentation
    if "AI_Segmentation" in name and seg_node.GetModifiedSinceRead():
        print(f"    -> Modified AI segmentation detected")
    
    # Try to export any modified segmentation
    if seg_node.GetModifiedSinceRead() or "corrected" in name.lower():
        print(f"  Exporting segmentation: {name}")
        
        # Export as labelmap volume first
        labelmap = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode", "ExportLabelmap")
        
        # Get the first segment (tumor) or all segments
        segment_ids = []
        segmentation = seg_node.GetSegmentation()
        for i in range(segmentation.GetNumberOfSegments()):
            segment_ids.append(segmentation.GetNthSegmentID(i))
        
        if segment_ids:
            slicer.modules.segmentations.logic().ExportSegmentsToLabelmapNode(
                seg_node, segment_ids, labelmap, seg_node.GetSegmentation().GetNthSegment(0))
            
            # Save labelmap as NIfTI
            slicer.util.saveNode(labelmap, output_path)
            print(f"  Saved to: {output_path}")
            saved = True
            
            # Clean up
            slicer.mrmlScene.RemoveNode(labelmap)
        break

if not saved:
    # Check for labelmap volumes directly
    labelmap_nodes = slicer.util.getNodesByClass("vtkMRMLLabelMapVolumeNode")
    for node in labelmap_nodes:
        name = node.GetName()
        if "corrected" in name.lower() or node.GetModifiedSinceRead():
            print(f"  Found modified labelmap: {name}")
            slicer.util.saveNode(node, output_path)
            saved = True
            break

if saved:
    print("Export complete!")
else:
    print("No modified segmentation found to export")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_corrected_seg.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_corrected_seg" 2>/dev/null || true
fi

# Also search for any NIfTI files that might be the corrected segmentation
echo "Searching for corrected segmentation files..."
SEARCH_PATHS=(
    "$CORRECTED_PATH"
    "$BRATS_DIR/corrected.nii.gz"
    "$BRATS_DIR/corrected_seg.nii.gz"
    "$BRATS_DIR/AI_Segmentation.nii.gz"
    "$BRATS_DIR/${SAMPLE_ID}_corrected.nii.gz"
    "/home/ga/corrected_segmentation.nii.gz"
    "/home/ga/Documents/corrected_segmentation.nii.gz"
)

FOUND_CORRECTED=""
for path in "${SEARCH_PATHS[@]}"; do
    if [ -f "$path" ]; then
        echo "Found potential corrected segmentation at: $path"
        FOUND_CORRECTED="$path"
        
        # Copy to expected location if different
        if [ "$path" != "$CORRECTED_PATH" ]; then
            cp "$path" "$CORRECTED_PATH" 2>/dev/null || true
        fi
        break
    fi
done

# Check if corrected file exists and was created during task
CORRECTED_EXISTS="false"
CORRECTED_SIZE=0
CORRECTED_MTIME=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$CORRECTED_PATH" ]; then
    CORRECTED_EXISTS="true"
    CORRECTED_SIZE=$(stat -c %s "$CORRECTED_PATH" 2>/dev/null || echo "0")
    CORRECTED_MTIME=$(stat -c %Y "$CORRECTED_PATH" 2>/dev/null || echo "0")
    
    if [ "$CORRECTED_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "Corrected segmentation was created during task"
    else
        echo "WARNING: Corrected segmentation exists but was not created during task"
    fi
fi

# Calculate verification metrics
echo "Computing verification metrics..."
python3 << PYEOF
import json
import sys
import os

try:
    import numpy as np
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "numpy", "nibabel"])
    import numpy as np
    import nibabel as nib

sample_id = "$SAMPLE_ID"
brats_dir = "$BRATS_DIR"
gt_dir = "$GROUND_TRUTH_DIR"
corrected_path = "$CORRECTED_PATH"
ai_seg_path = "$AI_SEG_PATH"
gt_seg_path = "$GT_SEG_PATH"
task_start = int("$TASK_START")
task_end = int("$TASK_END")

# Load initial state
initial_state = {}
try:
    with open("/tmp/initial_state.json", "r") as f:
        initial_state = json.load(f)
except:
    pass

initial_dice = initial_state.get("initial_dice", 0)
initial_fp = initial_state.get("initial_false_positives", 0)
initial_fn = initial_state.get("initial_false_negatives", 0)

# Load ground truth
gt_nii = nib.load(gt_seg_path)
gt_data = gt_nii.get_fdata().astype(np.int32)
gt_binary = (gt_data > 0)

# Load AI segmentation
ai_nii = nib.load(ai_seg_path)
ai_data = ai_nii.get_fdata().astype(np.int32)
ai_binary = (ai_data > 0)

# Try to load corrected segmentation
corrected_dice = 0
final_fp = initial_fp
final_fn = initial_fn
dice_improvement = 0
fp_reduction = 0
fn_recovery = 0
corrected_loaded = False
corrected_different_from_ai = False
corrected_different_from_gt = False

if os.path.exists(corrected_path):
    try:
        corrected_nii = nib.load(corrected_path)
        corrected_data = corrected_nii.get_fdata().astype(np.int32)
        corrected_binary = (corrected_data > 0)
        corrected_loaded = True
        
        # Check if corrected is different from AI seg
        diff_from_ai = np.sum(corrected_binary != ai_binary)
        corrected_different_from_ai = diff_from_ai > 100  # At least 100 voxels different
        
        # Check if corrected is different from GT (shouldn't be identical)
        diff_from_gt = np.sum(corrected_binary != gt_binary)
        corrected_different_from_gt = diff_from_gt > 10
        
        # Calculate final Dice
        intersection = np.sum(corrected_binary & gt_binary)
        corrected_dice = 2 * intersection / (np.sum(corrected_binary) + np.sum(gt_binary)) if (np.sum(corrected_binary) + np.sum(gt_binary)) > 0 else 0
        
        # Calculate improvement
        dice_improvement = corrected_dice - initial_dice
        
        # Calculate error changes
        final_fp = int(np.sum(corrected_binary & ~gt_binary))
        final_fn = int(np.sum(gt_binary & ~corrected_binary))
        
        # Calculate reduction rates
        if initial_fp > 0:
            fp_reduction = (initial_fp - final_fp) / initial_fp
        if initial_fn > 0:
            fn_recovery = (initial_fn - final_fn) / initial_fn
            
        print(f"Corrected segmentation analysis:")
        print(f"  Initial Dice: {initial_dice:.4f}")
        print(f"  Final Dice: {corrected_dice:.4f}")
        print(f"  Dice Improvement: {dice_improvement:.4f}")
        print(f"  FP Reduction: {fp_reduction*100:.1f}%")
        print(f"  FN Recovery: {fn_recovery*100:.1f}%")
        
    except Exception as e:
        print(f"Error loading corrected segmentation: {e}")

# Load error info from broken segmentation creation
errors_info = {}
errors_path = os.path.join(gt_dir, f"{sample_id}_broken_errors.json")
if os.path.exists(errors_path):
    with open(errors_path, "r") as f:
        errors_info = json.load(f)

# Create result JSON
result = {
    "sample_id": sample_id,
    "task_start_time": task_start,
    "task_end_time": task_end,
    "slicer_was_running": "$SLICER_RUNNING" == "true",
    "corrected_file_exists": "$CORRECTED_EXISTS" == "true",
    "corrected_file_size": int("$CORRECTED_SIZE"),
    "corrected_file_mtime": int("$CORRECTED_MTIME"),
    "file_created_during_task": "$FILE_CREATED_DURING_TASK" == "true",
    "corrected_loaded": corrected_loaded,
    "corrected_different_from_ai": corrected_different_from_ai,
    "corrected_different_from_gt": corrected_different_from_gt,
    "initial_dice": float(initial_dice),
    "final_dice": float(corrected_dice),
    "dice_improvement": float(dice_improvement),
    "initial_false_positives": int(initial_fp),
    "final_false_positives": int(final_fp),
    "false_positive_reduction": float(fp_reduction),
    "initial_false_negatives": int(initial_fn),
    "final_false_negatives": int(final_fn),
    "false_negative_recovery": float(fn_recovery),
    "gt_tumor_voxels": int(np.sum(gt_binary)),
    "errors_info": errors_info
}

# Write result
with open("/tmp/seg_correction_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result saved to /tmp/seg_correction_result.json")
PYEOF

# Set permissions on result file
chmod 666 /tmp/seg_correction_result.json 2>/dev/null || true

echo ""
echo "=== Export Complete ==="
cat /tmp/seg_correction_result.json