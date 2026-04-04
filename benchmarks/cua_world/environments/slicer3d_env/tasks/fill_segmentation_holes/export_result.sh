#!/bin/bash
echo "=== Exporting Fill Segmentation Holes Result ==="

source /workspace/scripts/task_utils.sh

DATA_DIR="/home/ga/Documents/SlicerData/LungHoles"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_FILE="$EXPORTS_DIR/filled_lung_segment.seg.nrrd"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

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
fi

# ============================================================
# Try to export segmentation from Slicer if not already saved
# ============================================================
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Attempting to export segmentation from Slicer..."
    
    cat > /tmp/export_seg.py << 'PYEOF'
import slicer
import os

exports_dir = "/home/ga/Documents/SlicerData/Exports"
os.makedirs(exports_dir, exist_ok=True)

# Find segmentation node
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

for seg_node in seg_nodes:
    print(f"Segmentation: {seg_node.GetName()}")
    segmentation = seg_node.GetSegmentation()
    for i in range(segmentation.GetNumberOfSegments()):
        seg_id = segmentation.GetNthSegmentID(i)
        segment = segmentation.GetSegment(seg_id)
        print(f"  Segment {i}: {segment.GetName()}")

# Export the segmentation
if seg_nodes:
    seg_node = seg_nodes[0]
    output_path = os.path.join(exports_dir, "filled_lung_segment.seg.nrrd")
    
    # Try to save using slicer utilities
    try:
        success = slicer.util.saveNode(seg_node, output_path)
        if success:
            print(f"Saved segmentation to {output_path}")
        else:
            # Alternative: export as labelmap
            labelmap = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
            slicer.modules.segmentations.logic().ExportAllSegmentsToLabelmapNode(
                seg_node, labelmap)
            nrrd_path = output_path.replace('.seg.nrrd', '.nrrd')
            slicer.util.saveNode(labelmap, nrrd_path)
            print(f"Saved as labelmap to {nrrd_path}")
            slicer.mrmlScene.RemoveNode(labelmap)
    except Exception as e:
        print(f"Error saving: {e}")

print("Export script complete")
PYEOF

    # Run export script with timeout
    timeout 20 su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_seg.py --no-main-window" > /tmp/slicer_export.log 2>&1 || true
    sleep 2
fi

# ============================================================
# Check output files
# ============================================================
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
OUTPUT_MTIME=0
FILE_CREATED_DURING_TASK="false"

# Check for various output file patterns
OUTPUT_PATHS=(
    "$OUTPUT_FILE"
    "$EXPORTS_DIR/filled_lung_segment.nrrd"
    "$EXPORTS_DIR/LungSegmentation.seg.nrrd"
    "$EXPORTS_DIR/RightLung.seg.nrrd"
)

ACTUAL_OUTPUT=""
for path in "${OUTPUT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        OUTPUT_EXISTS="true"
        ACTUAL_OUTPUT="$path"
        OUTPUT_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        OUTPUT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
        echo "Found output file: $path ($(($OUTPUT_SIZE / 1024)) KB)"
        break
    fi
done

# ============================================================
# Analyze the output segmentation
# ============================================================
FINAL_VOLUME_VOXELS=0
FINAL_VOLUME_ML=0
FINAL_BBOX_MIN="[0,0,0]"
FINAL_BBOX_MAX="[0,0,0]"
EULER_IMPROVED="false"
SEGMENT_FOUND="false"

if [ "$OUTPUT_EXISTS" = "true" ] && [ -n "$ACTUAL_OUTPUT" ]; then
    echo "Analyzing output segmentation..."
    
    python3 << PYEOF
import json
import sys
import numpy as np

try:
    import nibabel as nib
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
    import nibabel as nib

from scipy.ndimage import label as scipy_label

output_path = "$ACTUAL_OUTPUT"
initial_stats_path = "/tmp/initial_segment_stats.json"

# Load initial stats
with open(initial_stats_path) as f:
    initial_stats = json.load(f)

initial_volume = initial_stats.get("initial_volume_voxels", 0)
initial_holes = initial_stats.get("num_hole_regions", 0)
initial_bbox_min = initial_stats.get("bounding_box_min", [0, 0, 0])
initial_bbox_max = initial_stats.get("bounding_box_max", [256, 256, 100])
spacing = initial_stats.get("spacing_mm", [0.78, 0.78, 2.5])
voxel_vol_mm3 = np.prod(spacing)

# Load output segmentation
try:
    # Handle different file formats
    if output_path.endswith('.seg.nrrd') or output_path.endswith('.nrrd'):
        # Try nrrd loader
        try:
            import nrrd
            data, header = nrrd.read(output_path)
        except:
            # Fall back to nibabel
            img = nib.load(output_path)
            data = img.get_fdata()
    else:
        img = nib.load(output_path)
        data = img.get_fdata()
    
    # Get the segment (non-zero voxels)
    seg_mask = data > 0
    final_volume_voxels = int(np.sum(seg_mask))
    final_volume_ml = final_volume_voxels * voxel_vol_mm3 / 1000.0
    
    # Calculate bounding box
    nonzero = np.argwhere(seg_mask)
    if len(nonzero) > 0:
        bbox_min = nonzero.min(axis=0).tolist()
        bbox_max = nonzero.max(axis=0).tolist()
    else:
        bbox_min = [0, 0, 0]
        bbox_max = list(data.shape)
    
    # Check if there are internal holes (for Euler check)
    # Load reference filled version to compare
    ref_path = "/var/lib/slicer/ground_truth/lung_filled_reference.nii.gz"
    if os.path.exists(ref_path):
        ref_img = nib.load(ref_path)
        ref_data = ref_img.get_fdata()
        ref_mask = ref_data > 0
        
        # Count holes in output
        hole_mask = ref_mask & ~seg_mask
        _, num_output_holes = scipy_label(hole_mask)
    else:
        num_output_holes = initial_holes  # Assume no improvement
    
    euler_improved = num_output_holes < initial_holes
    
    # Calculate volume change
    if initial_volume > 0:
        volume_change_pct = 100.0 * (final_volume_voxels - initial_volume) / initial_volume
    else:
        volume_change_pct = 0
    
    # Check bounding box stability
    bbox_stable = True
    for i in range(3):
        if abs(bbox_min[i] - initial_bbox_min[i]) > data.shape[i] * 0.1:
            bbox_stable = False
        if abs(bbox_max[i] - initial_bbox_max[i]) > data.shape[i] * 0.1:
            bbox_stable = False
    
    result = {
        "segment_found": True,
        "final_volume_voxels": final_volume_voxels,
        "final_volume_ml": round(final_volume_ml, 2),
        "initial_volume_voxels": initial_volume,
        "initial_volume_ml": round(initial_volume * voxel_vol_mm3 / 1000.0, 2),
        "volume_change_percent": round(volume_change_pct, 2),
        "bbox_min": bbox_min,
        "bbox_max": bbox_max,
        "initial_bbox_min": initial_bbox_min,
        "initial_bbox_max": initial_bbox_max,
        "bbox_stable": bbox_stable,
        "num_output_holes": int(num_output_holes),
        "initial_holes": int(initial_holes),
        "euler_improved": euler_improved
    }
    
    print(json.dumps(result))
    
except Exception as e:
    print(json.dumps({
        "segment_found": False,
        "error": str(e)
    }))
PYEOF
) > /tmp/seg_analysis.json 2>/dev/null

    # Parse analysis results
    if [ -f /tmp/seg_analysis.json ]; then
        SEGMENT_FOUND=$(python3 -c "import json; print(json.load(open('/tmp/seg_analysis.json')).get('segment_found', False))" 2>/dev/null || echo "false")
        FINAL_VOLUME_VOXELS=$(python3 -c "import json; print(json.load(open('/tmp/seg_analysis.json')).get('final_volume_voxels', 0))" 2>/dev/null || echo "0")
        FINAL_VOLUME_ML=$(python3 -c "import json; print(json.load(open('/tmp/seg_analysis.json')).get('final_volume_ml', 0))" 2>/dev/null || echo "0")
        VOLUME_CHANGE_PCT=$(python3 -c "import json; print(json.load(open('/tmp/seg_analysis.json')).get('volume_change_percent', 0))" 2>/dev/null || echo "0")
        BBOX_STABLE=$(python3 -c "import json; print('true' if json.load(open('/tmp/seg_analysis.json')).get('bbox_stable', False) else 'false')" 2>/dev/null || echo "false")
        EULER_IMPROVED=$(python3 -c "import json; print('true' if json.load(open('/tmp/seg_analysis.json')).get('euler_improved', False) else 'false')" 2>/dev/null || echo "false")
    fi
fi

# ============================================================
# Load initial stats for comparison
# ============================================================
INITIAL_VOLUME_VOXELS=$(python3 -c "import json; print(json.load(open('/tmp/initial_segment_stats.json')).get('initial_volume_voxels', 0))" 2>/dev/null || echo "0")
INITIAL_VOLUME_ML=$(python3 -c "import json; print(json.load(open('/tmp/initial_segment_stats.json')).get('initial_volume_ml', 0))" 2>/dev/null || echo "0")
EXPECTED_INCREASE_PCT=$(python3 -c "import json; print(json.load(open('/tmp/initial_segment_stats.json')).get('volume_increase_expected_percent', 0))" 2>/dev/null || echo "0")

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$ACTUAL_OUTPUT",
    "output_size_bytes": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "segment_found": $SEGMENT_FOUND,
    "initial_volume_voxels": $INITIAL_VOLUME_VOXELS,
    "initial_volume_ml": $INITIAL_VOLUME_ML,
    "final_volume_voxels": $FINAL_VOLUME_VOXELS,
    "final_volume_ml": $FINAL_VOLUME_ML,
    "volume_change_percent": ${VOLUME_CHANGE_PCT:-0},
    "expected_increase_percent": $EXPECTED_INCREASE_PCT,
    "bbox_stable": $BBOX_STABLE,
    "euler_improved": $EULER_IMPROVED,
    "screenshot_exists": $([ -f /tmp/task_final.png ] && echo "true" || echo "false")
}
EOF

# Move to final location
rm -f /tmp/fill_holes_result.json 2>/dev/null || sudo rm -f /tmp/fill_holes_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/fill_holes_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/fill_holes_result.json
chmod 666 /tmp/fill_holes_result.json 2>/dev/null || sudo chmod 666 /tmp/fill_holes_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/fill_holes_result.json
echo ""

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer 2>/dev/null || pkill -f "Slicer" 2>/dev/null || true

echo "=== Export Complete ==="