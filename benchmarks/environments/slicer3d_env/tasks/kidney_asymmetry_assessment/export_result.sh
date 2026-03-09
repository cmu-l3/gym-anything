#!/bin/bash
echo "=== Exporting Kidney Asymmetry Assessment Result ==="

source /workspace/scripts/task_utils.sh

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_SEG="$AMOS_DIR/kidney_segmentation.seg.nrrd"
OUTPUT_REPORT="$AMOS_DIR/kidney_asymmetry_report.json"

# Get task timestamps for anti-gaming
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/kidney_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export segmentation from Slicer
    cat > /tmp/export_kidney_seg.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

# Find segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

exported = False
segment_info = {"segments": []}

for seg_node in seg_nodes:
    seg = seg_node.GetSegmentation()
    n_segments = seg.GetNumberOfSegments()
    print(f"  Segmentation '{seg_node.GetName()}' has {n_segments} segment(s)")
    
    for i in range(n_segments):
        segment_id = seg.GetNthSegmentID(i)
        segment = seg.GetSegment(segment_id)
        segment_name = segment.GetName()
        print(f"    Segment {i}: '{segment_name}'")
        segment_info["segments"].append({
            "id": segment_id,
            "name": segment_name,
            "index": i
        })
    
    if n_segments > 0:
        # Export as NRRD
        seg_path = os.path.join(output_dir, "kidney_segmentation.seg.nrrd")
        success = slicer.util.saveNode(seg_node, seg_path)
        if success:
            print(f"  Exported segmentation to {seg_path}")
            exported = True
        
        # Also try NIfTI export for verification
        nifti_path = os.path.join(output_dir, "kidney_segmentation.nii.gz")
        try:
            labelmapNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
            slicer.modules.segmentations.logic().ExportAllSegmentsToLabelmapNode(
                seg_node, labelmapNode)
            slicer.util.saveNode(labelmapNode, nifti_path)
            slicer.mrmlScene.RemoveNode(labelmapNode)
            print(f"  Exported labelmap to {nifti_path}")
        except Exception as e:
            print(f"  Could not export NIfTI: {e}")

# Save segment info
info_path = os.path.join(output_dir, "segment_info.json")
with open(info_path, "w") as f:
    json.dump(segment_info, f, indent=2)

if not exported:
    print("WARNING: No segmentation was exported")

print("Export script complete")
PYEOF

    # Run the export script in Slicer headless
    timeout 30 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-main-window --python-script /tmp/export_kidney_seg.py > /tmp/slicer_export.log 2>&1 || true
    sleep 3
fi

# Check for agent's segmentation file
SEG_EXISTS="false"
SEG_PATH=""
SEG_SIZE=0
SEG_CREATED_DURING_TASK="false"

POSSIBLE_SEG_PATHS=(
    "$OUTPUT_SEG"
    "$AMOS_DIR/kidney_segmentation.nii.gz"
    "$AMOS_DIR/Segmentation.seg.nrrd"
    "$AMOS_DIR/Segmentation.nrrd"
    "/home/ga/Documents/kidney_segmentation.seg.nrrd"
)

for path in "${POSSIBLE_SEG_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SEG_EXISTS="true"
        SEG_PATH="$path"
        SEG_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        SEG_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        # Check if created during task
        if [ "$SEG_MTIME" -gt "$TASK_START" ]; then
            SEG_CREATED_DURING_TASK="true"
        fi
        
        echo "Found segmentation at: $path (size: $SEG_SIZE bytes)"
        
        # Copy to expected location if needed
        if [ "$path" != "$OUTPUT_SEG" ]; then
            cp "$path" "$OUTPUT_SEG" 2>/dev/null || true
        fi
        break
    fi
done

# Check for agent's report file
REPORT_EXISTS="false"
REPORT_PATH=""
REPORT_CREATED_DURING_TASK="false"
REPORTED_LEFT_VOL=""
REPORTED_RIGHT_VOL=""
REPORTED_ASYMMETRY=""
REPORTED_SMALLER=""
REPORTED_CLASS=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/report.json"
    "$AMOS_DIR/kidney_report.json"
    "/home/ga/Documents/kidney_asymmetry_report.json"
    "/home/ga/kidney_asymmetry_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        REPORT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
            REPORT_CREATED_DURING_TASK="true"
        fi
        
        echo "Found report at: $path"
        
        # Extract values from report
        REPORTED_LEFT_VOL=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('left_kidney_volume_ml', ''))" 2>/dev/null || echo "")
        REPORTED_RIGHT_VOL=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('right_kidney_volume_ml', ''))" 2>/dev/null || echo "")
        REPORTED_ASYMMETRY=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('asymmetry_percentage', ''))" 2>/dev/null || echo "")
        REPORTED_SMALLER=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('smaller_kidney', ''))" 2>/dev/null || echo "")
        REPORTED_CLASS=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('classification', ''))" 2>/dev/null || echo "")
        
        # Copy to expected location if needed
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        break
    fi
done

# Copy files for verification
echo "Preparing files for verification..."

# Copy ground truth
cp "$GROUND_TRUTH_DIR/${CASE_ID}_labels.nii.gz" /tmp/gt_labels.nii.gz 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/${CASE_ID}_kidney_gt.json" /tmp/gt_kidney_info.json 2>/dev/null || true
chmod 644 /tmp/gt_labels.nii.gz /tmp/gt_kidney_info.json 2>/dev/null || true

# Copy agent segmentation (try NIfTI version first for easier processing)
if [ -f "$AMOS_DIR/kidney_segmentation.nii.gz" ]; then
    cp "$AMOS_DIR/kidney_segmentation.nii.gz" /tmp/agent_seg.nii.gz 2>/dev/null || true
    chmod 644 /tmp/agent_seg.nii.gz 2>/dev/null || true
elif [ -f "$OUTPUT_SEG" ]; then
    cp "$OUTPUT_SEG" /tmp/agent_seg.seg.nrrd 2>/dev/null || true
    chmod 644 /tmp/agent_seg.seg.nrrd 2>/dev/null || true
fi

# Copy agent report
if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_report.json 2>/dev/null || true
fi

# Copy segment info if available
if [ -f "$AMOS_DIR/segment_info.json" ]; then
    cp "$AMOS_DIR/segment_info.json" /tmp/segment_info.json 2>/dev/null || true
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer 2>/dev/null || true

# Create result JSON
echo "Creating result JSON..."
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "segmentation_exists": $SEG_EXISTS,
    "segmentation_path": "$SEG_PATH",
    "segmentation_size_bytes": $SEG_SIZE,
    "segmentation_created_during_task": $SEG_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "reported_left_volume_ml": "$REPORTED_LEFT_VOL",
    "reported_right_volume_ml": "$REPORTED_RIGHT_VOL",
    "reported_asymmetry_pct": "$REPORTED_ASYMMETRY",
    "reported_smaller_kidney": "$REPORTED_SMALLER",
    "reported_classification": "$REPORTED_CLASS",
    "screenshot_exists": $([ -f "/tmp/kidney_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/gt_kidney_info.json" ] && echo "true" || echo "false"),
    "case_id": "$CASE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/kidney_task_result.json 2>/dev/null || sudo rm -f /tmp/kidney_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/kidney_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/kidney_task_result.json
chmod 666 /tmp/kidney_task_result.json 2>/dev/null || sudo chmod 666 /tmp/kidney_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/kidney_task_result.json
echo ""
echo "=== Export Complete ==="