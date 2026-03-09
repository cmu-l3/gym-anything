#!/bin/bash
echo "=== Exporting Interpolate Sparse Segmentation Result ==="

source /workspace/scripts/task_utils.sh

# Get paths
BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_DIR="$BRATS_DIR/interpolated_scene"

if [ -f /tmp/task_sample_id.txt ]; then
    SAMPLE_ID=$(cat /tmp/task_sample_id.txt)
else
    SAMPLE_ID="BraTS2021_00000"
fi

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
# Export final segmentation from Slicer
# ============================================================
FINAL_SEG_FILE="$OUTPUT_DIR/final_tumor_seg.nii.gz"
mkdir -p "$OUTPUT_DIR"

if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Exporting final segmentation from Slicer..."
    
    cat > /tmp/export_final_seg.py << 'PYEOF'
import slicer
import os
import json
import numpy as np

output_dir = os.environ.get("OUTPUT_DIR", "/home/ga/Documents/SlicerData/BraTS/interpolated_scene")
os.makedirs(output_dir, exist_ok=True)

final_stats = {
    "segmentation_found": False,
    "final_voxel_count": 0,
    "final_slice_count": 0,
    "segments_in_scene": 0
}

# Find segmentation node
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

for seg_node in seg_nodes:
    segmentation = seg_node.GetSegmentation()
    num_segments = segmentation.GetNumberOfSegments()
    final_stats["segments_in_scene"] += num_segments
    print(f"  Segmentation '{seg_node.GetName()}' has {num_segments} segment(s)")
    
    for i in range(num_segments):
        segment_id = segmentation.GetNthSegmentID(i)
        segment = segmentation.GetSegment(segment_id)
        segment_name = segment.GetName()
        print(f"    Segment: {segment_name}")
        
        # Look for our tumor segment (may have been renamed or modified)
        if "tumor" in segment_name.lower() or "sparse" in segment_name.lower():
            final_stats["segmentation_found"] = True
            
            # Get the reference volume
            ref_volume = None
            volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
            for v in volume_nodes:
                if "flair" in v.GetName().lower():
                    ref_volume = v
                    break
            if ref_volume is None and volume_nodes:
                ref_volume = volume_nodes[0]
            
            if ref_volume:
                # Export as labelmap
                labelmap_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
                slicer.modules.segmentations.logic().ExportSegmentsToLabelmapNode(
                    seg_node, [segment_id], labelmap_node, ref_volume)
                
                # Get array and compute statistics
                seg_array = slicer.util.arrayFromVolume(labelmap_node)
                
                final_voxels = int(np.sum(seg_array > 0))
                final_stats["final_voxel_count"] = final_voxels
                
                # Count slices with segmentation
                slices_with_seg = sum(1 for z in range(seg_array.shape[0]) if np.any(seg_array[z, :, :] > 0))
                final_stats["final_slice_count"] = slices_with_seg
                final_stats["total_slices"] = seg_array.shape[0]
                
                # Check for gaps (consecutive empty slices in the middle)
                seg_slices = [z for z in range(seg_array.shape[0]) if np.any(seg_array[z, :, :] > 0)]
                if seg_slices:
                    max_gap = 0
                    for j in range(1, len(seg_slices)):
                        gap = seg_slices[j] - seg_slices[j-1] - 1
                        max_gap = max(max_gap, gap)
                    final_stats["max_consecutive_gap"] = max_gap
                    final_stats["slice_range"] = [int(min(seg_slices)), int(max(seg_slices))]
                
                # Calculate centroid
                if final_voxels > 0:
                    coords = np.argwhere(seg_array > 0)
                    centroid = coords.mean(axis=0).tolist()
                    final_stats["centroid_voxels"] = centroid
                
                # Save the labelmap as NIfTI
                output_path = os.path.join(output_dir, "final_tumor_seg.nii.gz")
                slicer.util.saveNode(labelmap_node, output_path)
                print(f"Saved final segmentation to: {output_path}")
                final_stats["export_path"] = output_path
                
                # Clean up
                slicer.mrmlScene.RemoveNode(labelmap_node)
            
            break  # Found our segment

# Save statistics
stats_path = os.path.join(output_dir, "final_stats.json")
with open(stats_path, "w") as f:
    json.dump(final_stats, f, indent=2)
print(f"\nFinal statistics: {json.dumps(final_stats, indent=2)}")
PYEOF

    export OUTPUT_DIR
    
    # Run export script in headless mode
    timeout 60 su - ga -c "DISPLAY=:1 OUTPUT_DIR='$OUTPUT_DIR' /opt/Slicer/Slicer --no-main-window --python-script /tmp/export_final_seg.py" > /tmp/slicer_export.log 2>&1 || true
    
    sleep 3
fi

# ============================================================
# Load initial and final statistics for comparison
# ============================================================
INITIAL_STATS_FILE="$GROUND_TRUTH_DIR/${SAMPLE_ID}_sparse_stats.json"
FINAL_STATS_FILE="$OUTPUT_DIR/final_stats.json"

# Default values
INITIAL_VOXELS="0"
FINAL_VOXELS="0"
INITIAL_SLICE_COUNT="0"
FINAL_SLICE_COUNT="0"
TOTAL_SLICES="0"
MAX_GAP="999"
SEGMENTATION_MODIFIED="false"
VOLUME_INCREASE="0"

# Read initial stats
if [ -f "$INITIAL_STATS_FILE" ]; then
    INITIAL_VOXELS=$(python3 -c "import json; print(json.load(open('$INITIAL_STATS_FILE')).get('sparse_voxel_count', 0))" 2>/dev/null || echo "0")
    INITIAL_SLICE_COUNT=$(python3 -c "import json; print(json.load(open('$INITIAL_STATS_FILE')).get('sparse_slice_count', 0))" 2>/dev/null || echo "0")
    TOTAL_SLICES=$(python3 -c "import json; print(json.load(open('$INITIAL_STATS_FILE')).get('total_slices', 0))" 2>/dev/null || echo "0")
    INITIAL_CENTROID=$(python3 -c "import json; print(json.load(open('$INITIAL_STATS_FILE')).get('centroid_mm', [0,0,0]))" 2>/dev/null || echo "[0,0,0]")
fi

# Read final stats
if [ -f "$FINAL_STATS_FILE" ]; then
    FINAL_VOXELS=$(python3 -c "import json; print(json.load(open('$FINAL_STATS_FILE')).get('final_voxel_count', 0))" 2>/dev/null || echo "0")
    FINAL_SLICE_COUNT=$(python3 -c "import json; print(json.load(open('$FINAL_STATS_FILE')).get('final_slice_count', 0))" 2>/dev/null || echo "0")
    MAX_GAP=$(python3 -c "import json; print(json.load(open('$FINAL_STATS_FILE')).get('max_consecutive_gap', 999))" 2>/dev/null || echo "999")
    SEGMENTATION_FOUND=$(python3 -c "import json; print(json.load(open('$FINAL_STATS_FILE')).get('segmentation_found', False))" 2>/dev/null || echo "False")
    FINAL_CENTROID=$(python3 -c "import json; print(json.load(open('$FINAL_STATS_FILE')).get('centroid_voxels', [0,0,0]))" 2>/dev/null || echo "[0,0,0]")
fi

# Calculate volume increase
if [ "$INITIAL_VOXELS" -gt 0 ] && [ "$FINAL_VOXELS" -gt 0 ]; then
    VOLUME_INCREASE=$(python3 -c "print(f'{$FINAL_VOXELS / $INITIAL_VOXELS:.3f}')" 2>/dev/null || echo "0")
fi

# Check if segmentation was modified
if [ "$FINAL_VOXELS" -gt "$INITIAL_VOXELS" ]; then
    SEGMENTATION_MODIFIED="true"
fi

# Calculate slice coverage
SLICE_COVERAGE="0"
if [ "$TOTAL_SLICES" -gt 0 ] && [ "$FINAL_SLICE_COUNT" -gt 0 ]; then
    # Estimate expected full slice count from initial stats
    EXPECTED_FULL_SLICES=$(python3 -c "import json; print(json.load(open('$INITIAL_STATS_FILE')).get('full_slice_count', $TOTAL_SLICES))" 2>/dev/null || echo "$TOTAL_SLICES")
    if [ "$EXPECTED_FULL_SLICES" -gt 0 ]; then
        SLICE_COVERAGE=$(python3 -c "print(f'{$FINAL_SLICE_COUNT / $EXPECTED_FULL_SLICES:.3f}')" 2>/dev/null || echo "0")
    fi
fi

# Check for saved scene files
SCENE_SAVED="false"
if ls "$OUTPUT_DIR"/*.mrml "$OUTPUT_DIR"/*.mrb "$BRATS_DIR"/*.mrml "$BRATS_DIR"/*.mrb 2>/dev/null | head -1 > /dev/null; then
    SCENE_SAVED="true"
fi

# Check if final segmentation file exists and was created during task
FINAL_SEG_EXISTS="false"
FINAL_SEG_CREATED_DURING_TASK="false"
if [ -f "$FINAL_SEG_FILE" ]; then
    FINAL_SEG_EXISTS="true"
    FINAL_SEG_MTIME=$(stat -c %Y "$FINAL_SEG_FILE" 2>/dev/null || echo "0")
    if [ "$FINAL_SEG_MTIME" -gt "$TASK_START" ]; then
        FINAL_SEG_CREATED_DURING_TASK="true"
    fi
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sample_id": "$SAMPLE_ID",
    "slicer_was_running": $SLICER_RUNNING,
    "initial_voxel_count": $INITIAL_VOXELS,
    "final_voxel_count": $FINAL_VOXELS,
    "volume_increase_ratio": $VOLUME_INCREASE,
    "initial_slice_count": $INITIAL_SLICE_COUNT,
    "final_slice_count": $FINAL_SLICE_COUNT,
    "total_slices": $TOTAL_SLICES,
    "slice_coverage": $SLICE_COVERAGE,
    "max_consecutive_gap": $MAX_GAP,
    "segmentation_modified": $SEGMENTATION_MODIFIED,
    "final_seg_exists": $FINAL_SEG_EXISTS,
    "final_seg_created_during_task": $FINAL_SEG_CREATED_DURING_TASK,
    "scene_saved": $SCENE_SAVED,
    "initial_centroid": $INITIAL_CENTROID,
    "final_centroid": $FINAL_CENTROID,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/interpolation_task_result.json 2>/dev/null || sudo rm -f /tmp/interpolation_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/interpolation_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/interpolation_task_result.json
chmod 666 /tmp/interpolation_task_result.json 2>/dev/null || sudo chmod 666 /tmp/interpolation_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Results ==="
cat /tmp/interpolation_task_result.json
echo ""

# Summary
echo ""
echo "=== Summary ==="
echo "Initial voxels: $INITIAL_VOXELS"
echo "Final voxels: $FINAL_VOXELS"
echo "Volume increase: ${VOLUME_INCREASE}x"
echo "Initial slices with seg: $INITIAL_SLICE_COUNT"
echo "Final slices with seg: $FINAL_SLICE_COUNT"
echo "Slice coverage: $SLICE_COVERAGE"
echo "Max gap: $MAX_GAP"
echo "Segmentation modified: $SEGMENTATION_MODIFIED"
echo ""
echo "=== Export Complete ==="