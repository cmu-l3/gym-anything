#!/bin/bash
echo "=== Exporting Segmentation QC Result ==="

source /workspace/scripts/task_utils.sh

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_SEG="$BRATS_DIR/corrected_segmentation.nii.gz"
OUTPUT_REPORT="$BRATS_DIR/qc_report.json"
BROKEN_SEG="$BRATS_DIR/ai_segmentation.nii.gz"

# Get sample ID
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/qc_final.png ga
sleep 1

# Get task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any unsaved segmentation from Slicer
    cat > /tmp/export_corrected_seg.py << 'PYEOF'
import slicer
import os

output_dir = "/home/ga/Documents/SlicerData/BraTS"
output_path = os.path.join(output_dir, "corrected_segmentation.nii.gz")

# Find segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

for seg_node in seg_nodes:
    print(f"  Segmentation: {seg_node.GetName()}")
    
    # Export as labelmap
    labelmap_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
    slicer.modules.segmentations.logic().ExportAllSegmentsToLabelmapNode(seg_node, labelmap_node)
    
    if labelmap_node:
        # Save to file
        slicer.util.saveNode(labelmap_node, output_path)
        print(f"Exported segmentation to {output_path}")
        slicer.mrmlScene.RemoveNode(labelmap_node)
        break

print("Export complete")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-main-window --python-script /tmp/export_corrected_seg.py > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_corrected_seg" 2>/dev/null || true
fi

# Check for corrected segmentation file
CORRECTED_EXISTS="false"
CORRECTED_MTIME="0"
CORRECTED_SIZE="0"

# Check multiple possible locations
POSSIBLE_SEG_PATHS=(
    "$OUTPUT_SEG"
    "$BRATS_DIR/corrected_segmentation.nii"
    "$BRATS_DIR/Segmentation.nii.gz"
    "$BRATS_DIR/segmentation.nii.gz"
    "/home/ga/Documents/corrected_segmentation.nii.gz"
)

for path in "${POSSIBLE_SEG_PATHS[@]}"; do
    if [ -f "$path" ]; then
        CORRECTED_EXISTS="true"
        CORRECTED_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        CORRECTED_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        echo "Found corrected segmentation at: $path (mtime: $CORRECTED_MTIME, size: $CORRECTED_SIZE)"
        if [ "$path" != "$OUTPUT_SEG" ]; then
            cp "$path" "$OUTPUT_SEG" 2>/dev/null || true
        fi
        break
    fi
done

# Check for QC report
REPORT_EXISTS="false"
REPORT_VALID="false"
REPORT_ERROR_COUNT="0"
REPORT_ERROR_TYPES="[]"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/report.json"
    "$BRATS_DIR/qc.json"
    "/home/ga/Documents/qc_report.json"
    "/home/ga/qc_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        echo "Found QC report at: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Validate and extract report contents
        REPORT_CONTENT=$(python3 << PYEOF
import json
import sys
try:
    with open("$path") as f:
        data = json.load(f)
    result = {
        "valid": True,
        "error_count": data.get("error_count", data.get("num_errors", 0)),
        "error_types": data.get("error_types", data.get("errors", [])),
        "has_corrections": "corrections_made" in data or "corrections" in data
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
)
        REPORT_VALID=$(echo "$REPORT_CONTENT" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('valid') else 'false')" 2>/dev/null || echo "false")
        REPORT_ERROR_COUNT=$(echo "$REPORT_CONTENT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('error_count', 0))" 2>/dev/null || echo "0")
        break
    fi
done

# Calculate detailed metrics
echo "Calculating verification metrics..."
python3 << 'PYEOF'
import os
import sys
import json

try:
    import numpy as np
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "numpy", "nibabel"])
    import numpy as np
    import nibabel as nib

gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
brats_dir = os.environ.get("BRATS_DIR", "/home/ga/Documents/SlicerData/BraTS")
sample_id = os.environ.get("SAMPLE_ID", "BraTS2021_00000")

gt_path = f"{gt_dir}/{sample_id}_seg.nii.gz"
broken_path = f"{brats_dir}/ai_segmentation.nii.gz"
corrected_path = f"{brats_dir}/corrected_segmentation.nii.gz"

metrics = {}

# Load initial metrics
initial_metrics_path = f"{gt_dir}/initial_metrics.json"
if os.path.exists(initial_metrics_path):
    with open(initial_metrics_path) as f:
        initial = json.load(f)
        metrics["initial_dice"] = initial.get("initial_dice", 0)
        metrics["initial_false_positives"] = initial.get("initial_false_positives", 0)
        metrics["initial_false_negatives"] = initial.get("initial_false_negatives", 0)

# Load ground truth
if os.path.exists(gt_path):
    gt_nii = nib.load(gt_path)
    gt = gt_nii.get_fdata() > 0
    metrics["gt_tumor_voxels"] = int(np.sum(gt))
    
    # Load broken segmentation
    if os.path.exists(broken_path):
        broken = nib.load(broken_path).get_fdata() > 0
        metrics["broken_tumor_voxels"] = int(np.sum(broken))
        
        # Calculate broken metrics
        broken_intersection = np.sum(gt & broken)
        broken_dice = 2 * broken_intersection / (np.sum(gt) + np.sum(broken)) if (np.sum(gt) + np.sum(broken)) > 0 else 0
        metrics["broken_dice"] = float(broken_dice)
        metrics["broken_false_positives"] = int(np.sum(broken & ~gt))
        metrics["broken_false_negatives"] = int(np.sum(gt & ~broken))
    
    # Load and evaluate corrected segmentation
    if os.path.exists(corrected_path):
        corrected = nib.load(corrected_path).get_fdata() > 0
        metrics["corrected_tumor_voxels"] = int(np.sum(corrected))
        
        # Calculate corrected metrics
        corrected_intersection = np.sum(gt & corrected)
        corrected_dice = 2 * corrected_intersection / (np.sum(gt) + np.sum(corrected)) if (np.sum(gt) + np.sum(corrected)) > 0 else 0
        metrics["corrected_dice"] = float(corrected_dice)
        metrics["corrected_false_positives"] = int(np.sum(corrected & ~gt))
        metrics["corrected_false_negatives"] = int(np.sum(gt & ~corrected))
        
        # Calculate improvement
        initial_dice = metrics.get("initial_dice", metrics.get("broken_dice", 0))
        metrics["dice_improvement"] = float(corrected_dice - initial_dice)
        
        # Check if modifications were made
        if os.path.exists(broken_path):
            voxels_changed = np.sum(broken != corrected)
            metrics["voxels_changed"] = int(voxels_changed)
            metrics["segmentation_modified"] = voxels_changed > 100
        
        print(f"Corrected Dice: {corrected_dice:.4f}")
        print(f"Dice Improvement: {metrics['dice_improvement']:.4f}")
        print(f"Voxels Changed: {metrics.get('voxels_changed', 0)}")
    else:
        metrics["corrected_exists"] = False
        print("No corrected segmentation found")
else:
    print("Ground truth not found")
    metrics["error"] = "Ground truth not found"

# Save metrics for verifier
with open("/tmp/qc_metrics.json", "w") as f:
    json.dump(metrics, f, indent=2)

print(f"Metrics saved to /tmp/qc_metrics.json")
PYEOF

# Also copy ground truth files for verifier access
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" /tmp/gt_segmentation.nii.gz 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_broken_errors.json" /tmp/broken_errors.json 2>/dev/null || true
chmod 644 /tmp/gt_segmentation.nii.gz /tmp/broken_errors.json /tmp/qc_metrics.json 2>/dev/null || true

if [ -f "$OUTPUT_SEG" ]; then
    cp "$OUTPUT_SEG" /tmp/corrected_segmentation.nii.gz 2>/dev/null || true
    chmod 644 /tmp/corrected_segmentation.nii.gz 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/qc_report.json 2>/dev/null || true
    chmod 644 /tmp/qc_report.json 2>/dev/null || true
fi

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "corrected_segmentation_exists": $CORRECTED_EXISTS,
    "corrected_segmentation_mtime": $CORRECTED_MTIME,
    "corrected_segmentation_size": $CORRECTED_SIZE,
    "qc_report_exists": $REPORT_EXISTS,
    "qc_report_valid": $REPORT_VALID,
    "sample_id": "$SAMPLE_ID",
    "screenshot_exists": $([ -f "/tmp/qc_final.png" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/qc_task_result.json 2>/dev/null || sudo rm -f /tmp/qc_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/qc_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/qc_task_result.json
chmod 666 /tmp/qc_task_result.json 2>/dev/null || sudo chmod 666 /tmp/qc_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/qc_task_result.json
echo ""

if [ -f /tmp/qc_metrics.json ]; then
    echo ""
    echo "=== QC Metrics ==="
    cat /tmp/qc_metrics.json
fi

echo ""
echo "=== Export Complete ==="