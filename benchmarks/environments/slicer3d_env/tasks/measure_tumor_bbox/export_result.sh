#!/bin/bash
echo "=== Exporting Tumor Bounding Box Measurement Result ==="

source /workspace/scripts/task_utils.sh

# Get sample ID
SAMPLE_ID="BraTS2021_00000"
if [ -f /tmp/bbox_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/bbox_sample_id)
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
OUTPUT_FILE="$BRATS_DIR/tumor_bbox_measurements.txt"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/bbox_final.png 2>/dev/null || true
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# Check if output file exists and was created during task
OUTPUT_EXISTS="false"
OUTPUT_CREATED_DURING_TASK="false"
OUTPUT_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_CREATED_DURING_TASK="true"
    fi
    
    echo "Output file found: $OUTPUT_FILE ($OUTPUT_SIZE bytes)"
    echo "Contents:"
    cat "$OUTPUT_FILE"
fi

# Parse measurements from output file
WIDTH_MM=""
DEPTH_MM=""
HEIGHT_MM=""
VOLUME_MM3=""
FORMAT_CORRECT="false"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo ""
    echo "Parsing measurements from output file..."
    
    # Try to extract values using various patterns
    WIDTH_MM=$(grep -iE "width|l-r|left.*right" "$OUTPUT_FILE" 2>/dev/null | grep -oE "[0-9]+\.?[0-9]*" | head -1 || echo "")
    DEPTH_MM=$(grep -iE "depth|a-p|anterior.*posterior" "$OUTPUT_FILE" 2>/dev/null | grep -oE "[0-9]+\.?[0-9]*" | head -1 || echo "")
    HEIGHT_MM=$(grep -iE "height|s-i|superior.*inferior" "$OUTPUT_FILE" 2>/dev/null | grep -oE "[0-9]+\.?[0-9]*" | head -1 || echo "")
    VOLUME_MM3=$(grep -iE "volume|total" "$OUTPUT_FILE" 2>/dev/null | grep -oE "[0-9]+\.?[0-9]*" | head -1 || echo "")
    
    # Check format
    if grep -qi "width" "$OUTPUT_FILE" && grep -qi "depth\|a-p" "$OUTPUT_FILE" && grep -qi "height\|s-i" "$OUTPUT_FILE"; then
        FORMAT_CORRECT="true"
    fi
    
    echo "  Width: $WIDTH_MM mm"
    echo "  Depth: $DEPTH_MM mm"  
    echo "  Height: $HEIGHT_MM mm"
    echo "  Volume: $VOLUME_MM3 mm³"
    echo "  Format correct: $FORMAT_CORRECT"
fi

# Try to get measurements from Slicer scene
SEGMENTATION_EXISTS="false"
SLICER_WIDTH=""
SLICER_DEPTH=""
SLICER_HEIGHT=""

if [ "$SLICER_RUNNING" = "true" ]; then
    echo ""
    echo "Attempting to extract measurements from Slicer scene..."
    
    cat > /tmp/extract_bbox.py << 'PYEOF'
import slicer
import json
import numpy as np
import os

result = {
    "segmentation_exists": False,
    "segment_count": 0,
    "width_mm": None,
    "depth_mm": None,
    "height_mm": None,
    "volume_mm3": None
}

# Look for segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

if seg_nodes:
    result["segmentation_exists"] = True
    seg_node = seg_nodes[0]
    
    seg = seg_node.GetSegmentation()
    result["segment_count"] = seg.GetNumberOfSegments()
    print(f"Segments: {result['segment_count']}")
    
    # Get labelmap representation
    labelmapNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
    slicer.modules.segmentations.logic().ExportAllSegmentsToLabelmapNode(
        seg_node, labelmapNode)
    
    # Get numpy array
    labelArray = slicer.util.arrayFromVolume(labelmapNode)
    
    if np.any(labelArray > 0):
        # Get voxel spacing
        spacing = labelmapNode.GetSpacing()
        print(f"Spacing: {spacing}")
        
        # Find non-zero voxels (tumor)
        coords = np.where(labelArray > 0)
        
        if len(coords[0]) > 0:
            # Calculate bounding box
            # Note: numpy array is ZYX ordering
            z_min, z_max = coords[0].min(), coords[0].max()
            y_min, y_max = coords[1].min(), coords[1].max()
            x_min, x_max = coords[2].min(), coords[2].max()
            
            # Calculate dimensions in mm (add 1 for inclusive span)
            result["width_mm"] = float((x_max - x_min + 1) * spacing[0])
            result["depth_mm"] = float((y_max - y_min + 1) * spacing[1])
            result["height_mm"] = float((z_max - z_min + 1) * spacing[2])
            result["volume_mm3"] = result["width_mm"] * result["depth_mm"] * result["height_mm"]
            
            print(f"Bounding box: W={result['width_mm']:.1f}, D={result['depth_mm']:.1f}, H={result['height_mm']:.1f} mm")
    
    # Clean up
    slicer.mrmlScene.RemoveNode(labelmapNode)

# Save result
with open("/tmp/slicer_bbox_extract.json", "w") as f:
    json.dump(result, f, indent=2)

print("Extraction complete")
PYEOF

    # Run extraction script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/extract_bbox.py --no-main-window > /tmp/slicer_extract.log 2>&1 &
    EXTRACT_PID=$!
    
    # Wait with timeout
    for i in {1..20}; do
        if [ -f /tmp/slicer_bbox_extract.json ]; then
            break
        fi
        sleep 1
    done
    kill $EXTRACT_PID 2>/dev/null || true
    
    # Parse extraction result
    if [ -f /tmp/slicer_bbox_extract.json ]; then
        SEGMENTATION_EXISTS=$(python3 -c "import json; print('true' if json.load(open('/tmp/slicer_bbox_extract.json')).get('segmentation_exists', False) else 'false')" 2>/dev/null || echo "false")
        SLICER_WIDTH=$(python3 -c "import json; v=json.load(open('/tmp/slicer_bbox_extract.json')).get('width_mm'); print(f'{v:.2f}' if v else '')" 2>/dev/null || echo "")
        SLICER_DEPTH=$(python3 -c "import json; v=json.load(open('/tmp/slicer_bbox_extract.json')).get('depth_mm'); print(f'{v:.2f}' if v else '')" 2>/dev/null || echo "")
        SLICER_HEIGHT=$(python3 -c "import json; v=json.load(open('/tmp/slicer_bbox_extract.json')).get('height_mm'); print(f'{v:.2f}' if v else '')" 2>/dev/null || echo "")
        
        echo "Slicer extraction results:"
        echo "  Segmentation exists: $SEGMENTATION_EXISTS"
        echo "  Width: $SLICER_WIDTH mm"
        echo "  Depth: $SLICER_DEPTH mm"
        echo "  Height: $SLICER_HEIGHT mm"
    fi
fi

# Also search for any segment statistics exports
STATS_FILE=$(find "$BRATS_DIR" -name "*statistics*.csv" -o -name "*Statistics*.csv" 2>/dev/null | head -1)
if [ -n "$STATS_FILE" ] && [ -f "$STATS_FILE" ]; then
    echo ""
    echo "Found statistics export: $STATS_FILE"
    head -20 "$STATS_FILE"
fi

# Load ground truth
GT_WIDTH=""
GT_DEPTH=""
GT_HEIGHT=""
GT_VOLUME=""

if [ -f /tmp/bbox_ground_truth.json ]; then
    GT_WIDTH=$(python3 -c "import json; print(f\"{json.load(open('/tmp/bbox_ground_truth.json'))['width_mm']:.2f}\")" 2>/dev/null || echo "")
    GT_DEPTH=$(python3 -c "import json; print(f\"{json.load(open('/tmp/bbox_ground_truth.json'))['depth_mm']:.2f}\")" 2>/dev/null || echo "")
    GT_HEIGHT=$(python3 -c "import json; print(f\"{json.load(open('/tmp/bbox_ground_truth.json'))['height_mm']:.2f}\")" 2>/dev/null || echo "")
    GT_VOLUME=$(python3 -c "import json; print(f\"{json.load(open('/tmp/bbox_ground_truth.json'))['bounding_volume_mm3']:.2f}\")" 2>/dev/null || echo "")
fi

# Create result JSON
echo ""
echo "Creating result JSON..."

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sample_id": "$SAMPLE_ID",
    "slicer_was_running": $SLICER_RUNNING,
    "output_file_exists": $OUTPUT_EXISTS,
    "output_created_during_task": $OUTPUT_CREATED_DURING_TASK,
    "output_file_size": $OUTPUT_SIZE,
    "format_correct": $FORMAT_CORRECT,
    "segmentation_exists": $SEGMENTATION_EXISTS,
    "measured_width_mm": "$WIDTH_MM",
    "measured_depth_mm": "$DEPTH_MM",
    "measured_height_mm": "$HEIGHT_MM",
    "measured_volume_mm3": "$VOLUME_MM3",
    "slicer_width_mm": "$SLICER_WIDTH",
    "slicer_depth_mm": "$SLICER_DEPTH",
    "slicer_height_mm": "$SLICER_HEIGHT",
    "gt_width_mm": "$GT_WIDTH",
    "gt_depth_mm": "$GT_DEPTH",
    "gt_height_mm": "$GT_HEIGHT",
    "gt_volume_mm3": "$GT_VOLUME",
    "screenshot_path": "/tmp/bbox_final.png"
}
EOF

# Move to final location
rm -f /tmp/bbox_task_result.json 2>/dev/null || sudo rm -f /tmp/bbox_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/bbox_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/bbox_task_result.json
chmod 666 /tmp/bbox_task_result.json 2>/dev/null || sudo chmod 666 /tmp/bbox_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/bbox_task_result.json"
cat /tmp/bbox_task_result.json
echo ""
echo "=== Export Complete ==="