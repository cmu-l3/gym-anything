#!/bin/bash
echo "=== Exporting Intersect Segments Boolean Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/intersection_task_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Create Python script to extract segmentation state
cat > /tmp/export_intersection_result.py << 'PYEOF'
import slicer
import json
import os
import numpy as np

output_path = "/tmp/intersection_task_result.json"

result = {
    "slicer_was_running": True,
    "segmentation_found": False,
    "intersection_segment_exists": False,
    "intersection_segment_name": "",
    "intersection_voxel_count": 0,
    "tumor_segment_exists": False,
    "tumor_voxel_count": 0,
    "motor_segment_exists": False,
    "motor_voxel_count": 0,
    "total_segments": 0,
    "segment_names": [],
    "created_during_task": False
}

try:
    # Find segmentation node
    seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
    
    if not seg_nodes:
        print("No segmentation nodes found")
        result["error"] = "No segmentation node found"
    else:
        seg_node = seg_nodes[0]
        result["segmentation_found"] = True
        
        segmentation = seg_node.GetSegmentation()
        num_segments = segmentation.GetNumberOfSegments()
        result["total_segments"] = num_segments
        
        print(f"Found {num_segments} segments")
        
        # Get reference volume for labelmap export
        ref_volume = None
        vol_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
        for v in vol_nodes:
            if "FLAIR" in v.GetName() or "BrainMRI" in v.GetName():
                ref_volume = v
                break
        if not ref_volume and vol_nodes:
            ref_volume = vol_nodes[0]
        
        # Iterate through segments
        for i in range(num_segments):
            seg_id = segmentation.GetNthSegmentID(i)
            segment = segmentation.GetSegment(seg_id)
            seg_name = segment.GetName()
            result["segment_names"].append(seg_name)
            
            print(f"Segment {i}: '{seg_name}'")
            
            # Export to labelmap to count voxels
            labelmap_node = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
            
            try:
                slicer.modules.segmentations.logic().ExportSegmentToLabelmapVolumeNode(
                    seg_node, seg_id, labelmap_node, ref_volume
                )
                
                array = slicer.util.arrayFromVolume(labelmap_node)
                voxel_count = int(np.sum(array > 0))
                
                print(f"  Voxel count: {voxel_count}")
                
            except Exception as e:
                print(f"  Could not export segment: {e}")
                voxel_count = 0
            finally:
                slicer.mrmlScene.RemoveNode(labelmap_node)
            
            # Check segment type
            name_lower = seg_name.lower()
            
            if "tumor" in name_lower and "overlap" not in name_lower and "motor" not in name_lower:
                result["tumor_segment_exists"] = True
                result["tumor_voxel_count"] = voxel_count
                
            elif "motor" in name_lower and "overlap" not in name_lower:
                result["motor_segment_exists"] = True
                result["motor_voxel_count"] = voxel_count
                
            elif "overlap" in name_lower or "intersect" in name_lower:
                result["intersection_segment_exists"] = True
                result["intersection_segment_name"] = seg_name
                result["intersection_voxel_count"] = voxel_count
                # Check if this looks like a newly created segment
                result["created_during_task"] = True
        
        # Also check for segments with similar names
        if not result["intersection_segment_exists"]:
            for name in result["segment_names"]:
                name_lower = name.lower()
                # Look for any segment that could be the intersection
                if ("tumor" in name_lower and "motor" in name_lower) or \
                   "intersection" in name_lower or \
                   "boolean" in name_lower or \
                   name_lower.startswith("segment_"):
                    # This might be the intersection - check if it's not tumor or motor
                    if name not in ["Tumor", "Motor_Region"]:
                        result["intersection_segment_exists"] = True
                        result["intersection_segment_name"] = name
                        print(f"Found potential intersection segment: {name}")

except Exception as e:
    result["error"] = str(e)
    print(f"Error: {e}")

# Save result
with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"\nResult saved to {output_path}")
print(json.dumps(result, indent=2))
PYEOF

# Run the export script in Slicer
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Extracting segmentation state from Slicer..."
    
    # Run Python script in Slicer's Python environment
    su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-main-window --python-script /tmp/export_intersection_result.py > /tmp/slicer_export.log 2>&1" &
    EXPORT_PID=$!
    
    # Wait for export with timeout
    for i in {1..30}; do
        if [ -f /tmp/intersection_task_result.json ]; then
            # Check if file has content
            if [ -s /tmp/intersection_task_result.json ]; then
                echo "Export completed"
                break
            fi
        fi
        sleep 1
    done
    
    # Kill export process if still running
    kill $EXPORT_PID 2>/dev/null || true
fi

# If export didn't produce results, create minimal result
if [ ! -f /tmp/intersection_task_result.json ] || [ ! -s /tmp/intersection_task_result.json ]; then
    echo "Creating fallback result..."
    cat > /tmp/intersection_task_result.json << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "segmentation_found": false,
    "intersection_segment_exists": false,
    "error": "Could not extract segmentation state",
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
EOF
fi

# Add timestamps to result
python3 << PYEOF
import json

try:
    with open("/tmp/intersection_task_result.json", "r") as f:
        result = json.load(f)
except:
    result = {}

result["task_start"] = $TASK_START
result["task_end"] = $TASK_END
result["slicer_was_running"] = "$SLICER_RUNNING" == "true"

with open("/tmp/intersection_task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Set permissions
chmod 666 /tmp/intersection_task_result.json 2>/dev/null || true

echo ""
echo "Result saved to /tmp/intersection_task_result.json"
cat /tmp/intersection_task_result.json
echo ""
echo "=== Export Complete ==="