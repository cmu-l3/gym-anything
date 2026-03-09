#!/bin/bash
echo "=== Exporting Gastric Volume Estimation Result ==="

source /workspace/scripts/task_utils.sh

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_SEG="$AMOS_DIR/gastric_segmentation.nii.gz"
OUTPUT_REPORT="$AMOS_DIR/bariatric_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/gastric_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export segmentation from Slicer before checking files
    echo "Attempting to export segmentation from Slicer scene..."
    cat > /tmp/export_gastric_seg.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

# Find segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

exported = False
for seg_node in seg_nodes:
    seg_name = seg_node.GetName()
    print(f"Processing segmentation: {seg_name}")
    
    # Export as labelmap
    labelmap_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
    slicer.modules.segmentations.logic().ExportAllSegmentsToLabelmapNode(
        seg_node, labelmap_node
    )
    
    # Save to file
    output_path = os.path.join(output_dir, "gastric_segmentation.nii.gz")
    success = slicer.util.saveNode(labelmap_node, output_path)
    
    if success:
        print(f"Exported segmentation to {output_path}")
        exported = True
        
        # Also compute volume using segment statistics
        try:
            import SegmentStatistics
            segStatLogic = SegmentStatistics.SegmentStatisticsLogic()
            segStatLogic.getParameterNode().SetParameter("Segmentation", seg_node.GetID())
            segStatLogic.computeStatistics()
            stats = segStatLogic.getStatistics()
            
            # Get volume for first segment
            for segmentId in stats["SegmentIDs"]:
                volume_mm3 = stats[segmentId, "LabelmapSegmentStatisticsPlugin.volume_mm3"]
                volume_ml = volume_mm3 / 1000.0
                print(f"Segment {segmentId} volume: {volume_ml:.2f} mL")
        except Exception as e:
            print(f"Could not compute statistics: {e}")
    
    slicer.mrmlScene.RemoveNode(labelmap_node)
    break  # Just process first segmentation

if not exported:
    print("No segmentation was exported")

print("Export script complete")
PYEOF

    # Run the export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_gastric_seg.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 15
    pkill -f "export_gastric_seg" 2>/dev/null || true
fi

# Check if agent saved a segmentation file
AGENT_SEG_EXISTS="false"
AGENT_SEG_PATH=""
AGENT_SEG_MTIME="0"
AGENT_SEG_SIZE="0"

# Check multiple possible locations
POSSIBLE_SEG_PATHS=(
    "$OUTPUT_SEG"
    "$AMOS_DIR/gastric_segmentation.nii"
    "$AMOS_DIR/Segmentation.nii.gz"
    "$AMOS_DIR/segmentation.nii.gz"
    "$AMOS_DIR/stomach_segmentation.nii.gz"
    "$AMOS_DIR/stomach.nii.gz"
    "/home/ga/Documents/gastric_segmentation.nii.gz"
    "/home/ga/gastric_segmentation.nii.gz"
)

for path in "${POSSIBLE_SEG_PATHS[@]}"; do
    if [ -f "$path" ]; then
        AGENT_SEG_EXISTS="true"
        AGENT_SEG_PATH="$path"
        AGENT_SEG_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        AGENT_SEG_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        echo "Found agent segmentation at: $path (size: $AGENT_SEG_SIZE bytes)"
        if [ "$path" != "$OUTPUT_SEG" ]; then
            cp "$path" "$OUTPUT_SEG" 2>/dev/null || true
        fi
        break
    fi
done

# Check if segmentation was created during task
SEG_CREATED_DURING_TASK="false"
if [ "$AGENT_SEG_EXISTS" = "true" ] && [ "$AGENT_SEG_MTIME" -gt "$TASK_START" ]; then
    SEG_CREATED_DURING_TASK="true"
    echo "Segmentation was created during task execution"
fi

# Check if agent saved a report file
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_VOLUME=""
REPORTED_CLASSIFICATION=""
REPORTED_FUNDUS=""
REPORTED_RECOMMENDATION=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/bariatric_report.json"
    "$AMOS_DIR/report.json"
    "$AMOS_DIR/gastric_report.json"
    "$AMOS_DIR/stomach_report.json"
    "/home/ga/Documents/bariatric_report.json"
    "/home/ga/bariatric_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        # Extract report fields
        REPORTED_VOLUME=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    v = d.get('volume_ml', d.get('volume', d.get('gastric_volume_ml', '')))
    print(float(v) if v else '')
except:
    print('')
" 2>/dev/null || echo "")
        REPORTED_CLASSIFICATION=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    print(d.get('classification', d.get('size_classification', d.get('category', ''))))
except:
    print('')
" 2>/dev/null || echo "")
        REPORTED_FUNDUS=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    v = d.get('fundus_included', d.get('fundus', None))
    print(str(v).lower() if v is not None else '')
except:
    print('')
" 2>/dev/null || echo "")
        REPORTED_RECOMMENDATION=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    print(d.get('surgical_recommendation', d.get('recommendation', '')))
except:
    print('')
" 2>/dev/null || echo "")
        echo "Reported volume: $REPORTED_VOLUME mL"
        echo "Reported classification: $REPORTED_CLASSIFICATION"
        break
    fi
done

# Calculate segmentation metrics if both agent and GT segmentations exist
COMPUTED_VOLUME_ML=""
COMPUTED_DICE=""
SEG_IS_CONTIGUOUS=""
SPILLOVER_LIVER_PCT=""
SPILLOVER_SPLEEN_PCT=""

if [ "$AGENT_SEG_EXISTS" = "true" ] && [ -f "$GROUND_TRUTH_DIR/${CASE_ID}_labels.nii.gz" ]; then
    echo "Computing segmentation metrics..."
    
    python3 << 'PYEOF'
import os
import sys
import json
import numpy as np

try:
    import nibabel as nib
    from scipy import ndimage
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel", "scipy"])
    import nibabel as nib
    from scipy import ndimage

case_id = os.environ.get("CASE_ID", "amos_0001")
gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
amos_dir = os.environ.get("AMOS_DIR", "/home/ga/Documents/SlicerData/AMOS")

agent_seg_path = os.path.join(amos_dir, "gastric_segmentation.nii.gz")
gt_labels_path = os.path.join(gt_dir, f"{case_id}_labels.nii.gz")

metrics = {}

try:
    # Load agent segmentation
    agent_nii = nib.load(agent_seg_path)
    agent_data = agent_nii.get_fdata()
    agent_mask = (agent_data > 0).astype(bool)
    
    # Load ground truth
    gt_nii = nib.load(gt_labels_path)
    gt_data = gt_nii.get_fdata().astype(np.int16)
    
    voxel_dims = agent_nii.header.get_zooms()[:3]
    voxel_volume_mm3 = float(np.prod(voxel_dims))
    
    # Stomach is label 9 in AMOS
    gt_stomach = (gt_data == 9)
    gt_liver = (gt_data == 6)
    gt_spleen = (gt_data == 1)
    
    # Calculate Dice coefficient
    intersection = np.sum(agent_mask & gt_stomach)
    sum_volumes = np.sum(agent_mask) + np.sum(gt_stomach)
    dice = 2.0 * intersection / sum_volumes if sum_volumes > 0 else 0.0
    
    # Calculate volume
    agent_volume_mm3 = np.sum(agent_mask) * voxel_volume_mm3
    agent_volume_ml = agent_volume_mm3 / 1000.0
    
    gt_volume_mm3 = np.sum(gt_stomach) * voxel_volume_mm3
    gt_volume_ml = gt_volume_mm3 / 1000.0
    
    # Check contiguity (single connected component)
    labeled, num_components = ndimage.label(agent_mask)
    is_contiguous = (num_components == 1)
    
    # Check spillover into other organs
    if np.sum(agent_mask) > 0:
        spillover_liver = np.sum(agent_mask & gt_liver) / np.sum(agent_mask) * 100
        spillover_spleen = np.sum(agent_mask & gt_spleen) / np.sum(agent_mask) * 100
    else:
        spillover_liver = 0.0
        spillover_spleen = 0.0
    
    metrics = {
        "dice_coefficient": round(dice, 4),
        "agent_volume_ml": round(agent_volume_ml, 2),
        "gt_volume_ml": round(gt_volume_ml, 2),
        "volume_error_percent": round(abs(agent_volume_ml - gt_volume_ml) / gt_volume_ml * 100, 2) if gt_volume_ml > 0 else 0,
        "is_contiguous": is_contiguous,
        "num_components": int(num_components),
        "spillover_liver_percent": round(spillover_liver, 2),
        "spillover_spleen_percent": round(spillover_spleen, 2),
        "agent_voxels": int(np.sum(agent_mask)),
        "gt_voxels": int(np.sum(gt_stomach))
    }
    
    print(f"Dice: {dice:.4f}")
    print(f"Agent volume: {agent_volume_ml:.2f} mL, GT volume: {gt_volume_ml:.2f} mL")
    print(f"Contiguous: {is_contiguous} ({num_components} components)")
    print(f"Spillover - Liver: {spillover_liver:.2f}%, Spleen: {spillover_spleen:.2f}%")
    
except Exception as e:
    print(f"Error computing metrics: {e}")
    metrics = {"error": str(e)}

# Save metrics
metrics_path = "/tmp/gastric_seg_metrics.json"
with open(metrics_path, "w") as f:
    json.dump(metrics, f, indent=2)
print(f"Metrics saved to {metrics_path}")
PYEOF

    # Read computed metrics
    if [ -f /tmp/gastric_seg_metrics.json ]; then
        COMPUTED_VOLUME_ML=$(python3 -c "import json; print(json.load(open('/tmp/gastric_seg_metrics.json')).get('agent_volume_ml', ''))" 2>/dev/null || echo "")
        COMPUTED_DICE=$(python3 -c "import json; print(json.load(open('/tmp/gastric_seg_metrics.json')).get('dice_coefficient', ''))" 2>/dev/null || echo "")
        SEG_IS_CONTIGUOUS=$(python3 -c "import json; v=json.load(open('/tmp/gastric_seg_metrics.json')).get('is_contiguous', False); print('true' if v else 'false')" 2>/dev/null || echo "false")
        SPILLOVER_LIVER_PCT=$(python3 -c "import json; print(json.load(open('/tmp/gastric_seg_metrics.json')).get('spillover_liver_percent', '0'))" 2>/dev/null || echo "0")
        SPILLOVER_SPLEEN_PCT=$(python3 -c "import json; print(json.load(open('/tmp/gastric_seg_metrics.json')).get('spillover_spleen_percent', '0'))" 2>/dev/null || echo "0")
    fi
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Copy files for verification
echo "Preparing files for verification..."

# Copy ground truth
cp "$GROUND_TRUTH_DIR/${CASE_ID}_labels.nii.gz" /tmp/gt_labels.nii.gz 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/${CASE_ID}_stomach_gt.json" /tmp/stomach_gt.json 2>/dev/null || true
chmod 644 /tmp/gt_labels.nii.gz /tmp/stomach_gt.json 2>/dev/null || true

# Copy agent segmentation
if [ -f "$OUTPUT_SEG" ]; then
    cp "$OUTPUT_SEG" /tmp/agent_gastric_seg.nii.gz 2>/dev/null || true
    chmod 644 /tmp/agent_gastric_seg.nii.gz 2>/dev/null || true
fi

# Copy agent report
if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_bariatric_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_bariatric_report.json 2>/dev/null || true
fi

# Copy metrics if computed
if [ -f /tmp/gastric_seg_metrics.json ]; then
    chmod 644 /tmp/gastric_seg_metrics.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "agent_segmentation_exists": $AGENT_SEG_EXISTS,
    "agent_segmentation_path": "$AGENT_SEG_PATH",
    "agent_segmentation_size_bytes": $AGENT_SEG_SIZE,
    "segmentation_created_during_task": $SEG_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "reported_volume_ml": "$REPORTED_VOLUME",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "reported_fundus_included": "$REPORTED_FUNDUS",
    "reported_recommendation": "$REPORTED_RECOMMENDATION",
    "computed_volume_ml": "$COMPUTED_VOLUME_ML",
    "computed_dice": "$COMPUTED_DICE",
    "segmentation_is_contiguous": $SEG_IS_CONTIGUOUS,
    "spillover_liver_percent": $SPILLOVER_LIVER_PCT,
    "spillover_spleen_percent": $SPILLOVER_SPLEEN_PCT,
    "screenshot_exists": $([ -f "/tmp/gastric_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/stomach_gt.json" ] && echo "true" || echo "false"),
    "case_id": "$CASE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/gastric_task_result.json 2>/dev/null || sudo rm -f /tmp/gastric_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/gastric_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/gastric_task_result.json
chmod 666 /tmp/gastric_task_result.json 2>/dev/null || sudo chmod 666 /tmp/gastric_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/gastric_task_result.json
echo ""
echo "=== Export Complete ==="