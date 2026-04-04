#!/bin/bash
echo "=== Exporting Liver Surgical Planning Result ==="

source /workspace/scripts/task_utils.sh

# Get the patient number used
if [ -f /tmp/ircadb_patient_num ]; then
    PATIENT_NUM=$(cat /tmp/ircadb_patient_num)
else
    PATIENT_NUM="5"
fi

IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
OUTPUT_SEG="$IRCADB_DIR/agent_segmentation.nii.gz"
OUTPUT_REPORT="$IRCADB_DIR/surgical_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/liver_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"

    # Try to export segmentation from Slicer before closing
    cat > /tmp/export_liver_seg.py << 'PYEOF'
import slicer
import os

output_dir = "/home/ga/Documents/SlicerData/IRCADb"
os.makedirs(output_dir, exist_ok=True)

# Find segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

for seg_node in seg_nodes:
    segmentation = seg_node.GetSegmentation()
    n_segments = segmentation.GetNumberOfSegments()
    print(f"  Segmentation '{seg_node.GetName()}': {n_segments} segments")
    for i in range(n_segments):
        segment = segmentation.GetNthSegment(i)
        print(f"    Segment {i}: {segment.GetName()}")

# Export as labelmap NIfTI
if seg_nodes:
    seg_node = seg_nodes[0]

    # Create a temporary labelmap node
    labelmap_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
    labelmap_node.SetName("ExportedLabelmap")

    # Get reference volume
    volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    ref_vol = volume_nodes[0] if volume_nodes else None

    # Export segmentation to labelmap
    if ref_vol:
        slicer.modules.segmentations.logic().ExportVisibleSegmentsToLabelmapNode(
            seg_node, labelmap_node, ref_vol)
    else:
        slicer.modules.segmentations.logic().ExportAllSegmentsToLabelmapNode(
            seg_node, labelmap_node)

    # Save labelmap as NIfTI
    output_path = os.path.join(output_dir, "agent_segmentation.nii.gz")
    slicer.util.saveNode(labelmap_node, output_path)
    print(f"Exported segmentation to {output_path}")

    # Clean up
    slicer.mrmlScene.RemoveNode(labelmap_node)
else:
    print("No segmentation nodes found in scene")

print("Export complete")
PYEOF

    # Run the export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_liver_seg.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_liver_seg" 2>/dev/null || true
fi

# Check if agent saved a segmentation file
AGENT_SEG_EXISTS="false"
AGENT_SEG_PATH=""

POSSIBLE_SEG_PATHS=(
    "$OUTPUT_SEG"
    "$IRCADB_DIR/Segmentation.nii.gz"
    "$IRCADB_DIR/segmentation.nii.gz"
    "$IRCADB_DIR/LiverSegmentation.nii.gz"
    "/home/ga/Documents/agent_segmentation.nii.gz"
    "/home/ga/agent_segmentation.nii.gz"
)

for path in "${POSSIBLE_SEG_PATHS[@]}"; do
    if [ -f "$path" ]; then
        AGENT_SEG_EXISTS="true"
        AGENT_SEG_PATH="$path"
        echo "Found agent segmentation at: $path"
        if [ "$path" != "$OUTPUT_SEG" ]; then
            cp "$path" "$OUTPUT_SEG" 2>/dev/null || true
        fi
        break
    fi
done

# Check if agent created a surgical report
REPORT_EXISTS="false"
REPORTED_TUMOR_VOL=""
REPORTED_TUMOR_COUNT=""
REPORTED_MIN_DISTANCE=""
REPORTED_INVASION=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$IRCADB_DIR/report.json"
    "$IRCADB_DIR/liver_report.json"
    "/home/ga/Documents/surgical_report.json"
    "/home/ga/surgical_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        echo "Found surgical report at: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        # Try to extract key values
        REPORTED_TUMOR_VOL=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('tumor_volume_ml', d.get('tumor_volume', '')))" 2>/dev/null || echo "")
        REPORTED_TUMOR_COUNT=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('tumor_count', d.get('number_of_tumors', '')))" 2>/dev/null || echo "")
        REPORTED_MIN_DISTANCE=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('min_distance_mm', d.get('minimum_distance_mm', '')))" 2>/dev/null || echo "")
        REPORTED_INVASION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('vascular_invasion', d.get('portal_vein_contact', '')))" 2>/dev/null || echo "")
        break
    fi
done

# Get segmentation file info
SEG_SIZE_BYTES=0
if [ -f "$OUTPUT_SEG" ]; then
    SEG_SIZE_BYTES=$(stat -c %s "$OUTPUT_SEG" 2>/dev/null || echo "0")
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Copy ground truth for verification
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/ircadb_patient${PATIENT_NUM}_seg.nii.gz" /tmp/liver_ground_truth_seg.nii.gz 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/ircadb_patient${PATIENT_NUM}_gt.json" /tmp/liver_ground_truth_stats.json 2>/dev/null || true
chmod 644 /tmp/liver_ground_truth_seg.nii.gz /tmp/liver_ground_truth_stats.json 2>/dev/null || true

if [ -f "$OUTPUT_SEG" ]; then
    cp "$OUTPUT_SEG" /tmp/liver_agent_segmentation.nii.gz 2>/dev/null || true
    chmod 644 /tmp/liver_agent_segmentation.nii.gz 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/liver_agent_report.json 2>/dev/null || true
    chmod 644 /tmp/liver_agent_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "agent_segmentation_exists": $AGENT_SEG_EXISTS,
    "agent_segmentation_path": "$AGENT_SEG_PATH",
    "agent_segmentation_size_bytes": $SEG_SIZE_BYTES,
    "report_exists": $REPORT_EXISTS,
    "reported_tumor_volume_ml": "$REPORTED_TUMOR_VOL",
    "reported_tumor_count": "$REPORTED_TUMOR_COUNT",
    "reported_min_distance_mm": "$REPORTED_MIN_DISTANCE",
    "reported_invasion": "$REPORTED_INVASION",
    "screenshot_exists": $([ -f "/tmp/liver_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/liver_ground_truth_seg.nii.gz" ] && echo "true" || echo "false"),
    "patient_num": "$PATIENT_NUM",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/liver_task_result.json 2>/dev/null || sudo rm -f /tmp/liver_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/liver_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/liver_task_result.json
chmod 666 /tmp/liver_task_result.json 2>/dev/null || sudo chmod 666 /tmp/liver_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/liver_task_result.json
echo ""
echo "=== Export Complete ==="
