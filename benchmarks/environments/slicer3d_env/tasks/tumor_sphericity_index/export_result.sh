#!/bin/bash
echo "=== Exporting Tumor Sphericity Index Result ==="

source /workspace/scripts/task_utils.sh

# Get task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
OUTPUT_SEG="$BRATS_DIR/agent_tumor_shape.nii.gz"
OUTPUT_REPORT="$BRATS_DIR/tumor_shape_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/sphericity_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export segmentation from Slicer before checking files
    cat > /tmp/export_shape_seg.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

# Find segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

if seg_nodes:
    # Export the first segmentation
    seg_node = seg_nodes[0]
    print(f"Exporting segmentation: {seg_node.GetName()}")
    
    # Export as labelmap
    labelmapNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
    slicer.modules.segmentations.logic().ExportAllSegmentsToLabelmapNode(
        seg_node, labelmapNode, slicer.vtkSegmentation.EXTENT_REFERENCE_GEOMETRY)
    
    # Save to file
    output_path = os.path.join(output_dir, "agent_tumor_shape.nii.gz")
    slicer.util.saveNode(labelmapNode, output_path)
    print(f"Saved segmentation to {output_path}")
    
    # Clean up temporary node
    slicer.mrmlScene.RemoveNode(labelmapNode)
else:
    print("No segmentation found in scene")

# Check for 3D models
model_nodes = slicer.util.getNodesByClass("vtkMRMLModelNode")
user_models = [m for m in model_nodes if not m.GetName().startswith("Slice")]
print(f"Found {len(user_models)} model node(s)")

print("Export complete")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_shape_seg.py --no-main-window > /tmp/slicer_export_shape.log 2>&1 &
    sleep 10
    pkill -f "export_shape_seg" 2>/dev/null || true
fi

# Check for agent's segmentation file
AGENT_SEG_EXISTS="false"
AGENT_SEG_PATH=""
SEG_SIZE_BYTES=0
SEG_CREATED_DURING_TASK="false"

POSSIBLE_SEG_PATHS=(
    "$OUTPUT_SEG"
    "$BRATS_DIR/agent_tumor_shape.nii"
    "$BRATS_DIR/Segmentation.nii.gz"
    "$BRATS_DIR/segmentation.nii.gz"
    "$BRATS_DIR/tumor_segmentation.nii.gz"
    "/home/ga/Documents/agent_tumor_shape.nii.gz"
)

for path in "${POSSIBLE_SEG_PATHS[@]}"; do
    if [ -f "$path" ]; then
        AGENT_SEG_EXISTS="true"
        AGENT_SEG_PATH="$path"
        SEG_SIZE_BYTES=$(stat -c %s "$path" 2>/dev/null || echo "0")
        SEG_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        # Check if created during task
        if [ "$SEG_MTIME" -gt "$TASK_START" ]; then
            SEG_CREATED_DURING_TASK="true"
        fi
        
        echo "Found agent segmentation at: $path (size: $SEG_SIZE_BYTES bytes)"
        if [ "$path" != "$OUTPUT_SEG" ]; then
            cp "$path" "$OUTPUT_SEG" 2>/dev/null || true
        fi
        break
    fi
done

# Check for agent's shape report
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_VOLUME=""
REPORTED_SURFACE_AREA=""
REPORTED_SPHERICITY=""
REPORTED_CLASSIFICATION=""
REPORT_COMPLETE="false"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/tumor_shape_report.json"
    "$BRATS_DIR/shape_report.json"
    "$BRATS_DIR/report.json"
    "/home/ga/Documents/tumor_shape_report.json"
    "/home/ga/tumor_shape_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found shape report at: $path"
        
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract reported values
        REPORTED_VOLUME=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
v = d.get('volume_ml', d.get('volume', d.get('tumor_volume_ml', '')))
print(v if v else '')
" 2>/dev/null || echo "")
        
        REPORTED_SURFACE_AREA=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
sa = d.get('surface_area_mm2', d.get('surface_area', d.get('area_mm2', '')))
print(sa if sa else '')
" 2>/dev/null || echo "")
        
        REPORTED_SPHERICITY=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
s = d.get('sphericity', d.get('sphericity_index', ''))
print(s if s else '')
" 2>/dev/null || echo "")
        
        REPORTED_CLASSIFICATION=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
c = d.get('morphology_class', d.get('classification', d.get('shape_class', '')))
print(c if c else '')
" 2>/dev/null || echo "")
        
        # Check if report has all required fields
        REPORT_COMPLETE=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
required = ['volume_ml', 'surface_area_mm2', 'sphericity', 'morphology_class']
alt_names = {
    'volume_ml': ['volume', 'tumor_volume_ml', 'vol_ml'],
    'surface_area_mm2': ['surface_area', 'area_mm2', 'sa_mm2'],
    'sphericity': ['sphericity_index', 'sph'],
    'morphology_class': ['classification', 'shape_class', 'class']
}
found = 0
for r in required:
    if r in d and d[r]:
        found += 1
    else:
        for alt in alt_names.get(r, []):
            if alt in d and d[alt]:
                found += 1
                break
print('true' if found >= 4 else 'false')
" 2>/dev/null || echo "false")
        
        echo "  Volume: $REPORTED_VOLUME mL"
        echo "  Surface Area: $REPORTED_SURFACE_AREA mm²"
        echo "  Sphericity: $REPORTED_SPHERICITY"
        echo "  Classification: $REPORTED_CLASSIFICATION"
        echo "  Report complete: $REPORT_COMPLETE"
        break
    fi
done

# Check for 3D visualization (screenshots or models)
VISUALIZATION_CREATED="false"
SCREENSHOT_COUNT=0

# Check for screenshots created during task
if [ -d "$BRATS_DIR" ]; then
    SCREENSHOT_COUNT=$(find "$BRATS_DIR" /home/ga/Documents/SlicerData/Screenshots -name "*.png" -newer /tmp/task_start_time.txt 2>/dev/null | wc -l)
fi

if [ "$SCREENSHOT_COUNT" -gt 0 ]; then
    echo "Found $SCREENSHOT_COUNT screenshots created during task"
    VISUALIZATION_CREATED="true"
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Copy files for verification
echo "Preparing files for verification..."

cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" /tmp/gt_seg.nii.gz 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_shape_gt.json" /tmp/gt_shape.json 2>/dev/null || true
chmod 644 /tmp/gt_seg.nii.gz /tmp/gt_shape.json 2>/dev/null || true

if [ -f "$OUTPUT_SEG" ]; then
    cp "$OUTPUT_SEG" /tmp/agent_seg.nii.gz 2>/dev/null || true
    chmod 644 /tmp/agent_seg.nii.gz 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_shape_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_shape_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "agent_segmentation_exists": $AGENT_SEG_EXISTS,
    "agent_segmentation_path": "$AGENT_SEG_PATH",
    "agent_segmentation_size_bytes": $SEG_SIZE_BYTES,
    "segmentation_created_during_task": $SEG_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_complete": $REPORT_COMPLETE,
    "reported_volume_ml": "$REPORTED_VOLUME",
    "reported_surface_area_mm2": "$REPORTED_SURFACE_AREA",
    "reported_sphericity": "$REPORTED_SPHERICITY",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "visualization_created": $VISUALIZATION_CREATED,
    "screenshot_count": $SCREENSHOT_COUNT,
    "sample_id": "$SAMPLE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/sphericity_task_result.json 2>/dev/null || sudo rm -f /tmp/sphericity_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/sphericity_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/sphericity_task_result.json
chmod 666 /tmp/sphericity_task_result.json 2>/dev/null || sudo chmod 666 /tmp/sphericity_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/sphericity_task_result.json
echo ""
echo "=== Export Complete ==="