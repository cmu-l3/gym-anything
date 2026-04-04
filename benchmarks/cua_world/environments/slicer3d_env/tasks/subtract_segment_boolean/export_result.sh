#!/bin/bash
set -e

echo "=== Exporting Boolean Subtraction Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

RESULT_DIR="/tmp/task_result"
RESULT_JSON="$RESULT_DIR/result.json"
mkdir -p "$RESULT_DIR"

# Get sample ID
SAMPLE_ID=$(cat /tmp/current_sample_id 2>/dev/null || echo "BraTS2021_00000")

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot "$RESULT_DIR/final_screenshot.png" 2>/dev/null || true

# Query Slicer for segmentation state
QUERY_SCRIPT="/tmp/query_segments.py"
cat > "$QUERY_SCRIPT" << 'PYEOF'
import slicer
import json
import numpy as np
import os

result = {
    "segmentation_found": False,
    "whole_tumor_found": False,
    "necrotic_found": False,
    "whole_tumor_voxels": 0,
    "necrotic_voxels": 0,
    "whole_tumor_volume_ml": 0.0,
    "necrotic_volume_ml": 0.0,
    "overlap_voxels": 0,
    "segments_list": [],
    "query_success": False
}

try:
    # Find segmentation node
    seg_node = None
    seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
    for node in seg_nodes:
        if "Tumor" in node.GetName():
            seg_node = node
            break
    
    if not seg_node:
        # Try to get any segmentation
        if seg_nodes:
            seg_node = seg_nodes[0]
    
    if seg_node:
        result["segmentation_found"] = True
        segmentation = seg_node.GetSegmentation()
        
        # Get reference volume for voxel size
        flair_node = None
        vol_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
        for node in vol_nodes:
            if "FLAIR" in node.GetName() or "flair" in node.GetName():
                flair_node = node
                break
        
        if not flair_node and vol_nodes:
            flair_node = vol_nodes[0]
        
        if flair_node:
            spacing = flair_node.GetSpacing()
            voxel_volume_mm3 = spacing[0] * spacing[1] * spacing[2]
        else:
            voxel_volume_mm3 = 1.0
        
        whole_tumor_array = None
        necrotic_array = None
        
        for i in range(segmentation.GetNumberOfSegments()):
            segment_id = segmentation.GetNthSegmentID(i)
            segment = segmentation.GetSegment(segment_id)
            segment_name = segment.GetName()
            result["segments_list"].append(segment_name)
            
            try:
                # Get segment as numpy array
                labelmap = slicer.util.arrayFromSegmentBinaryLabelmap(seg_node, segment_id, flair_node)
                voxel_count = int(np.sum(labelmap > 0))
                volume_ml = voxel_count * voxel_volume_mm3 / 1000.0
                
                if "WholeTumor" in segment_name or "ViableTumor" in segment_name or "Viable" in segment_name:
                    result["whole_tumor_found"] = True
                    result["whole_tumor_voxels"] = voxel_count
                    result["whole_tumor_volume_ml"] = round(volume_ml, 3)
                    whole_tumor_array = labelmap.copy()
                elif "Necrotic" in segment_name:
                    result["necrotic_found"] = True
                    result["necrotic_voxels"] = voxel_count
                    result["necrotic_volume_ml"] = round(volume_ml, 3)
                    necrotic_array = labelmap.copy()
            except Exception as e:
                print(f"Error processing segment {segment_name}: {e}")
        
        # Calculate overlap between WholeTumor and NecroticCore
        if whole_tumor_array is not None and necrotic_array is not None:
            overlap = np.sum((whole_tumor_array > 0) & (necrotic_array > 0))
            result["overlap_voxels"] = int(overlap)
        
        result["query_success"] = True

except Exception as e:
    result["error"] = str(e)

# Save result
output_path = "/tmp/segment_query_result.json"
with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Execute query in Slicer if running
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Querying Slicer segmentation state..."
    
    # Run query script
    DISPLAY=:1 /opt/Slicer/Slicer --no-splash --no-main-window --python-script "$QUERY_SCRIPT" > /tmp/slicer_query.log 2>&1 &
    QUERY_PID=$!
    
    # Wait for query with timeout
    TIMEOUT=45
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        if [ -f /tmp/segment_query_result.json ]; then
            # Check if file has content
            if [ -s /tmp/segment_query_result.json ]; then
                echo "Query result obtained"
                break
            fi
        fi
        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done
    
    kill $QUERY_PID 2>/dev/null || true
fi

# Build final result JSON
echo "Building result JSON..."

python3 << PYEOF
import json
import os

result = {
    "slicer_running": $( [ "$SLICER_RUNNING" = "true" ] && echo "true" || echo "false" ),
    "sample_id": "$SAMPLE_ID",
    "screenshot_exists": os.path.exists("$RESULT_DIR/final_screenshot.png"),
    "task_start_time": int("$TASK_START") if "$TASK_START".isdigit() else 0,
    "task_end_time": int("$TASK_END") if "$TASK_END".isdigit() else 0
}

# Add segment query results
try:
    if os.path.exists("/tmp/segment_query_result.json"):
        with open("/tmp/segment_query_result.json", "r") as f:
            seg_result = json.load(f)
            result.update(seg_result)
except Exception as e:
    result["segment_query_error"] = str(e)

# Save combined result
with open("$RESULT_JSON", "w") as f:
    json.dump(result, f, indent=2)

print("Result saved to $RESULT_JSON")
print(json.dumps(result, indent=2))
PYEOF

# Copy ground truth for verification
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_boolean_gt.json" "$RESULT_DIR/ground_truth.json" 2>/dev/null || {
    echo "Warning: Could not copy ground truth file"
    # Create minimal ground truth
    echo '{"sample_id": "'$SAMPLE_ID'", "tolerance_percent": 5.0}' > "$RESULT_DIR/ground_truth.json"
}

# Copy screenshot for VLM verification
cp /tmp/task_initial_state.png "$RESULT_DIR/initial_screenshot.png" 2>/dev/null || true

echo ""
echo "=== Export Complete ==="
echo "Results exported to $RESULT_DIR"
ls -la "$RESULT_DIR"