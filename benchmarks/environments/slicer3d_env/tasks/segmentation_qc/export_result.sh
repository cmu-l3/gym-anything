#!/bin/bash
echo "=== Exporting Segmentation QC Result ==="

source /workspace/scripts/task_utils.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
OUTPUT_SEG="$BRATS_DIR/corrected_segmentation.nii.gz"
OUTPUT_REPORT="$BRATS_DIR/qc_report.json"
BROKEN_SEG="$BRATS_DIR/ai_segmentation.nii.gz"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/qc_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"

    # Try to export corrected segmentation from Slicer
    cat > /tmp/export_qc_seg.py << 'PYEOF'
import slicer
import os

output_dir = "/home/ga/Documents/SlicerData/BraTS"
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

# Export the (presumably corrected) segmentation as labelmap
if seg_nodes:
    # Use the first segmentation node (which should be the corrected one)
    seg_node = seg_nodes[0]

    # Create temporary labelmap node
    labelmap_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
    labelmap_node.SetName("CorrectedLabelmap")

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

    # Save as NIfTI
    output_path = os.path.join(output_dir, "corrected_segmentation.nii.gz")
    slicer.util.saveNode(labelmap_node, output_path)
    print(f"Exported corrected segmentation to {output_path}")

    slicer.mrmlScene.RemoveNode(labelmap_node)
else:
    print("No segmentation nodes found")

print("Export complete")
PYEOF

    # Run the export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_qc_seg.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_qc_seg" 2>/dev/null || true
fi

# Check if agent saved a corrected segmentation
CORRECTED_SEG_EXISTS="false"
CORRECTED_SEG_PATH=""

POSSIBLE_SEG_PATHS=(
    "$OUTPUT_SEG"
    "$BRATS_DIR/corrected_segmentation.nii"
    "$BRATS_DIR/Segmentation.nii.gz"
    "$BRATS_DIR/segmentation.nii.gz"
    "$BRATS_DIR/CorrectedSegmentation.nii.gz"
    "/home/ga/Documents/corrected_segmentation.nii.gz"
    "/home/ga/corrected_segmentation.nii.gz"
)

for path in "${POSSIBLE_SEG_PATHS[@]}"; do
    if [ -f "$path" ]; then
        CORRECTED_SEG_EXISTS="true"
        CORRECTED_SEG_PATH="$path"
        echo "Found corrected segmentation at: $path"
        if [ "$path" != "$OUTPUT_SEG" ]; then
            cp "$path" "$OUTPUT_SEG" 2>/dev/null || true
        fi
        break
    fi
done

# Check if agent created a QC report
REPORT_EXISTS="false"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/qc_report.json"
    "$BRATS_DIR/report.json"
    "$BRATS_DIR/quality_report.json"
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

# Copy files needed for verification
echo "Preparing files for verification..."

# Ground truth
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" /tmp/qc_ground_truth_seg.nii.gz 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_broken_errors.json" /tmp/qc_broken_errors.json 2>/dev/null || true
chmod 644 /tmp/qc_ground_truth_seg.nii.gz /tmp/qc_broken_errors.json 2>/dev/null || true

# Broken segmentation (the input the agent received)
if [ -f "$BROKEN_SEG" ]; then
    cp "$BROKEN_SEG" /tmp/qc_broken_segmentation.nii.gz 2>/dev/null || true
    chmod 644 /tmp/qc_broken_segmentation.nii.gz 2>/dev/null || true
fi

# Agent's corrected segmentation
if [ -f "$OUTPUT_SEG" ]; then
    cp "$OUTPUT_SEG" /tmp/qc_corrected_segmentation.nii.gz 2>/dev/null || true
    chmod 644 /tmp/qc_corrected_segmentation.nii.gz 2>/dev/null || true
fi

# Agent's QC report
if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/qc_agent_report.json 2>/dev/null || true
    chmod 644 /tmp/qc_agent_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "corrected_segmentation_exists": $CORRECTED_SEG_EXISTS,
    "corrected_segmentation_path": "$CORRECTED_SEG_PATH",
    "corrected_segmentation_size_bytes": $SEG_SIZE_BYTES,
    "report_exists": $REPORT_EXISTS,
    "broken_segmentation_exists": $([ -f "/tmp/qc_broken_segmentation.nii.gz" ] && echo "true" || echo "false"),
    "screenshot_exists": $([ -f "/tmp/qc_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/qc_ground_truth_seg.nii.gz" ] && echo "true" || echo "false"),
    "sample_id": "$SAMPLE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/qc_task_result.json 2>/dev/null || sudo rm -f /tmp/qc_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/qc_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/qc_task_result.json
chmod 666 /tmp/qc_task_result.json 2>/dev/null || sudo chmod 666 /tmp/qc_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/qc_task_result.json
echo ""
echo "=== Export Complete ==="
