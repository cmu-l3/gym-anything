#!/bin/bash
echo "=== Exporting Bladder Volume Assessment Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Get task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_SEG="$AMOS_DIR/bladder_segmentation.nii.gz"
OUTPUT_REPORT="$AMOS_DIR/bladder_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/bladder_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
    
    # Try to export segmentation from Slicer before closing
    cat > /tmp/export_bladder_seg.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

# Find segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

for node in seg_nodes:
    seg_name = node.GetName()
    print(f"  Processing segmentation: {seg_name}")
    
    # Export to NIfTI
    output_path = os.path.join(output_dir, "bladder_segmentation.nii.gz")
    
    # Create labelmap from segmentation
    labelmapNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
    slicer.modules.segmentations.logic().ExportAllSegmentsToLabelmapNode(node, labelmapNode)
    
    # Save labelmap
    slicer.util.saveNode(labelmapNode, output_path)
    print(f"  Exported to: {output_path}")
    
    # Also try to get volume statistics
    try:
        import SegmentStatistics
        segStatLogic = SegmentStatistics.SegmentStatisticsLogic()
        segStatLogic.getParameterNode().SetParameter("Segmentation", node.GetID())
        
        # Get reference volume
        vol_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
        if vol_nodes:
            segStatLogic.getParameterNode().SetParameter("ScalarVolume", vol_nodes[0].GetID())
        
        segStatLogic.computeStatistics()
        stats = segStatLogic.getStatistics()
        
        # Get volume for first segment (assumed to be bladder)
        segmentation = node.GetSegmentation()
        if segmentation.GetNumberOfSegments() > 0:
            segment_id = segmentation.GetNthSegmentID(0)
            volume_mm3 = stats[segment_id, "LabelmapSegmentStatisticsPlugin.volume_mm3"]
            volume_ml = volume_mm3 / 1000.0
            print(f"  Bladder volume: {volume_ml:.1f} mL")
    except Exception as e:
        print(f"  Could not compute statistics: {e}")

print("Export complete")
PYEOF

    # Run the export script in Slicer (briefly)
    timeout 15 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_bladder_seg.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
fi

# Check if agent saved a segmentation file
AGENT_SEG_EXISTS="false"
AGENT_SEG_PATH=""
SEG_SIZE_BYTES=0
SEG_TIMESTAMP=0

# Check multiple possible locations for segmentation
POSSIBLE_SEG_PATHS=(
    "$OUTPUT_SEG"
    "$AMOS_DIR/bladder_segmentation.nii"
    "$AMOS_DIR/Segmentation.nii.gz"
    "$AMOS_DIR/segmentation.nii.gz"
    "$AMOS_DIR/Bladder.nii.gz"
    "/home/ga/Documents/bladder_segmentation.nii.gz"
    "/home/ga/bladder_segmentation.nii.gz"
)

for path in "${POSSIBLE_SEG_PATHS[@]}"; do
    if [ -f "$path" ]; then
        AGENT_SEG_EXISTS="true"
        AGENT_SEG_PATH="$path"
        SEG_SIZE_BYTES=$(stat -c %s "$path" 2>/dev/null || echo "0")
        SEG_TIMESTAMP=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        echo "Found agent segmentation at: $path ($(echo "$SEG_SIZE_BYTES / 1024" | bc) KB)"
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_SEG" ]; then
            cp "$path" "$OUTPUT_SEG" 2>/dev/null || true
        fi
        break
    fi
done

# Check if segmentation was created after task start (anti-gaming)
SEG_CREATED_DURING_TASK="false"
if [ "$AGENT_SEG_EXISTS" = "true" ] && [ "$SEG_TIMESTAMP" -gt "$TASK_START" ]; then
    SEG_CREATED_DURING_TASK="true"
    echo "Segmentation was created during task"
else
    echo "Warning: Segmentation timestamp issue (created before task or not found)"
fi

# Check if agent created a report
REPORT_EXISTS="false"
REPORT_TIMESTAMP=0
REPORTED_VOLUME_ML="null"
REPORTED_STATUS="null"
REPORTED_SIGNIFICANCE="null"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/bladder_report.json"
    "$AMOS_DIR/report.json"
    "/home/ga/Documents/bladder_report.json"
    "/home/ga/bladder_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_TIMESTAMP=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        echo "Found report at: $path"
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract report fields
        REPORTED_VOLUME_ML=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    vol = d.get('volume_ml', d.get('volume', d.get('bladder_volume_ml', None)))
    if vol is not None:
        print(float(vol))
    else:
        print('null')
except Exception as e:
    print('null')
" 2>/dev/null || echo "null")

        REPORTED_STATUS=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    status = d.get('distension_status', d.get('status', d.get('classification', None)))
    if status:
        print(repr(status))
    else:
        print('null')
except:
    print('null')
" 2>/dev/null || echo "null")

        REPORTED_SIGNIFICANCE=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    sig = d.get('clinical_significance', d.get('clinically_significant', None))
    if sig is not None:
        print(str(sig).lower())
    else:
        print('null')
except:
    print('null')
" 2>/dev/null || echo "null")

        echo "Reported volume: $REPORTED_VOLUME_ML mL"
        echo "Reported status: $REPORTED_STATUS"
        echo "Reported significance: $REPORTED_SIGNIFICANCE"
        break
    fi
done

REPORT_CREATED_DURING_TASK="false"
if [ "$REPORT_EXISTS" = "true" ] && [ "$REPORT_TIMESTAMP" -gt "$TASK_START" ]; then
    REPORT_CREATED_DURING_TASK="true"
fi

# Copy ground truth for verification
echo "Preparing ground truth for verification..."
cp "$GROUND_TRUTH_DIR/${CASE_ID}_bladder_gt.nii.gz" /tmp/ground_truth_bladder.nii.gz 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/${CASE_ID}_bladder_gt.json" /tmp/ground_truth_bladder.json 2>/dev/null || true
chmod 644 /tmp/ground_truth_bladder.nii.gz /tmp/ground_truth_bladder.json 2>/dev/null || true

if [ -f "$OUTPUT_SEG" ]; then
    cp "$OUTPUT_SEG" /tmp/agent_bladder_segmentation.nii.gz 2>/dev/null || true
    chmod 644 /tmp/agent_bladder_segmentation.nii.gz 2>/dev/null || true
fi

# Check for screenshot (final state evidence)
SCREENSHOT_EXISTS="false"
if [ -f "/tmp/bladder_final.png" ]; then
    SCREENSHOT_EXISTS="true"
fi

# Create result JSON
echo "Creating result JSON..."
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "case_id": "$CASE_ID",
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "segmentation_exists": $AGENT_SEG_EXISTS,
    "segmentation_path": "$OUTPUT_SEG",
    "segmentation_size_bytes": $SEG_SIZE_BYTES,
    "segmentation_timestamp": $SEG_TIMESTAMP,
    "segmentation_created_during_task": $SEG_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$OUTPUT_REPORT",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "reported_volume_ml": $REPORTED_VOLUME_ML,
    "reported_distension_status": $REPORTED_STATUS,
    "reported_clinical_significance": $REPORTED_SIGNIFICANCE,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "ground_truth_available": $([ -f "/tmp/ground_truth_bladder.nii.gz" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move result to final location
rm -f /tmp/bladder_task_result.json 2>/dev/null || sudo rm -f /tmp/bladder_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/bladder_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/bladder_task_result.json
chmod 666 /tmp/bladder_task_result.json 2>/dev/null || sudo chmod 666 /tmp/bladder_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/bladder_task_result.json
echo ""
echo "=== Export Complete ==="