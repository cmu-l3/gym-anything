#!/bin/bash
echo "=== Exporting Visceral Fat Quantification Result ==="

source /workspace/scripts/task_utils.sh

# Get the case ID used
if [ -f /tmp/fat_task_case_id.txt ]; then
    CASE_ID=$(cat /tmp/fat_task_case_id.txt)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_SEG="$AMOS_DIR/fat_segmentation.nii.gz"
OUTPUT_REPORT="$AMOS_DIR/fat_analysis_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/fat_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"

    # Try to export segmentation and calculate statistics from Slicer
    cat > /tmp/export_fat_seg.py << 'PYEOF'
import slicer
import os
import json
import numpy as np

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

# Find segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

if seg_nodes:
    seg_node = seg_nodes[0]
    
    # Export segmentation to file
    seg_path = os.path.join(output_dir, "fat_segmentation.nii.gz")
    
    # Get the reference volume
    vol_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    ref_vol = vol_nodes[0] if vol_nodes else None
    
    if ref_vol:
        # Export as labelmap
        labelmapVolumeNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
        slicer.modules.segmentations.logic().ExportAllSegmentsToLabelmapNode(
            seg_node, labelmapVolumeNode, slicer.vtkSegmentation.EXTENT_REFERENCE_GEOMETRY)
        slicer.util.saveNode(labelmapVolumeNode, seg_path)
        print(f"Segmentation exported to {seg_path}")
    
    # Get segment IDs and compute statistics
    segmentation = seg_node.GetSegmentation()
    segment_ids = [segmentation.GetNthSegmentID(i) for i in range(segmentation.GetNumberOfSegments())]
    
    sat_area = 0
    vat_area = 0
    
    # Try to identify SAT and VAT segments by name
    for seg_id in segment_ids:
        segment = segmentation.GetSegment(seg_id)
        name = segment.GetName().lower()
        print(f"  Segment: {name}")
        
        # Calculate segment statistics
        import SegmentStatistics
        segStatLogic = SegmentStatistics.SegmentStatisticsLogic()
        segStatLogic.getParameterNode().SetParameter("Segmentation", seg_node.GetID())
        segStatLogic.getParameterNode().SetParameter("ScalarVolume", ref_vol.GetID() if ref_vol else "")
        segStatLogic.computeStatistics()
        stats = segStatLogic.getStatistics()
        
        for stat_seg_id in stats.keys():
            if "LabelmapSegmentStatisticsPlugin.volume_cm3" in stats[stat_seg_id]:
                vol = stats[stat_seg_id]["LabelmapSegmentStatisticsPlugin.volume_cm3"]
                print(f"    Volume: {vol} cm³")
        
        if "sat" in name or "subcutaneous" in name:
            sat_area = stats.get(seg_id, {}).get("LabelmapSegmentStatisticsPlugin.volume_cm3", 0)
        elif "vat" in name or "visceral" in name:
            vat_area = stats.get(seg_id, {}).get("LabelmapSegmentStatisticsPlugin.volume_cm3", 0)

print("Export complete")
PYEOF

    # Run the export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_fat_seg.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 15
    pkill -f "export_fat_seg" 2>/dev/null || true
fi

# Check if agent saved segmentation file
SEGMENTATION_EXISTS="false"
SEGMENTATION_PATH=""
SEG_SIZE_BYTES=0
SEG_CREATED_DURING_TASK="false"

POSSIBLE_SEG_PATHS=(
    "$OUTPUT_SEG"
    "$AMOS_DIR/fat_segmentation.nii"
    "$AMOS_DIR/Segmentation.nii.gz"
    "$AMOS_DIR/segmentation.nii.gz"
    "/home/ga/Documents/fat_segmentation.nii.gz"
)

for path in "${POSSIBLE_SEG_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SEGMENTATION_EXISTS="true"
        SEGMENTATION_PATH="$path"
        SEG_SIZE_BYTES=$(stat -c %s "$path" 2>/dev/null || echo "0")
        SEG_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$SEG_MTIME" -gt "$TASK_START" ]; then
            SEG_CREATED_DURING_TASK="true"
        fi
        echo "Found segmentation at: $path"
        if [ "$path" != "$OUTPUT_SEG" ]; then
            cp "$path" "$OUTPUT_SEG" 2>/dev/null || true
        fi
        break
    fi
done

# Check if agent saved a report
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_SAT=""
REPORTED_VAT=""
REPORTED_RATIO=""
REPORTED_CLASSIFICATION=""
REPORTED_SLICE=""
REPORT_CREATED_DURING_TASK="false"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/fat_report.json"
    "$AMOS_DIR/report.json"
    "/home/ga/Documents/fat_analysis_report.json"
    "/home/ga/fat_analysis_report.json"
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
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract report fields
        REPORTED_SAT=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('sat_area_cm2', d.get('SAT_area_cm2', d.get('sat', ''))))" 2>/dev/null || echo "")
        REPORTED_VAT=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('vat_area_cm2', d.get('VAT_area_cm2', d.get('vat', ''))))" 2>/dev/null || echo "")
        REPORTED_RATIO=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('vat_sat_ratio', d.get('VAT_SAT_ratio', d.get('ratio', ''))))" 2>/dev/null || echo "")
        REPORTED_CLASSIFICATION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('fat_distribution', d.get('classification', '')))" 2>/dev/null || echo "")
        REPORTED_SLICE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('slice_index', d.get('measurement_level', '')))" 2>/dev/null || echo "")
        
        echo "Reported SAT: $REPORTED_SAT cm²"
        echo "Reported VAT: $REPORTED_VAT cm²"
        echo "Reported ratio: $REPORTED_RATIO"
        echo "Reported classification: $REPORTED_CLASSIFICATION"
        echo "Reported slice: $REPORTED_SLICE"
        break
    fi
done

# Copy ground truth for verification
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/${CASE_ID}_fat_gt.json" /tmp/fat_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/fat_ground_truth.json 2>/dev/null || true

if [ -f "$OUTPUT_SEG" ]; then
    cp "$OUTPUT_SEG" /tmp/agent_fat_seg.nii.gz 2>/dev/null || true
    chmod 644 /tmp/agent_fat_seg.nii.gz 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_fat_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_fat_report.json 2>/dev/null || true
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "segmentation_exists": $SEGMENTATION_EXISTS,
    "segmentation_path": "$SEGMENTATION_PATH",
    "segmentation_size_bytes": $SEG_SIZE_BYTES,
    "segmentation_created_during_task": $SEG_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "reported_sat_area_cm2": "$REPORTED_SAT",
    "reported_vat_area_cm2": "$REPORTED_VAT",
    "reported_vat_sat_ratio": "$REPORTED_RATIO",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "reported_slice_index": "$REPORTED_SLICE",
    "screenshot_exists": $([ -f "/tmp/fat_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/fat_ground_truth.json" ] && echo "true" || echo "false"),
    "case_id": "$CASE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/fat_task_result.json 2>/dev/null || sudo rm -f /tmp/fat_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/fat_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/fat_task_result.json
chmod 666 /tmp/fat_task_result.json 2>/dev/null || sudo chmod 666 /tmp/fat_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/fat_task_result.json
echo ""
echo "=== Export Complete ==="