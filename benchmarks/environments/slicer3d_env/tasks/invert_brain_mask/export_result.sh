#!/bin/bash
echo "=== Exporting Invert Brain Mask Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot first
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Create export script to run inside Slicer
EXPORT_SCRIPT="/tmp/export_segmentation_state.py"
cat > "$EXPORT_SCRIPT" << 'PYEOF'
import slicer
import json
import os
import time
import numpy as np

print("=== Exporting segmentation state ===")

result = {
    "slicer_was_running": True,
    "export_timestamp": time.time(),
    "segments": [],
    "segment_names": [],
    "segment_voxels": {},
    "total_segments": 0,
    "brain_segment_found": False,
    "inverse_segment_found": False,
    "inverse_segment_name": "",
    "brain_voxels": 0,
    "inverse_voxels": 0,
    "overlap_voxels": 0,
    "total_volume_voxels": 0,
    "coverage_ratio": 0.0,
    "overlap_ratio": 0.0,
    "error": None
}

try:
    # Find segmentation node
    segmentationNodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
    
    if not segmentationNodes:
        result["error"] = "No segmentation node found"
        print("ERROR: No segmentation node found")
    else:
        segNode = segmentationNodes[0]
        segmentation = segNode.GetSegmentation()
        
        # Get all segment IDs and names
        segmentIds = []
        for i in range(segmentation.GetNumberOfSegments()):
            segId = segmentation.GetNthSegmentID(i)
            segmentIds.append(segId)
            segment = segmentation.GetSegment(segId)
            segName = segment.GetName()
            result["segments"].append({"id": segId, "name": segName})
            result["segment_names"].append(segName)
        
        result["total_segments"] = len(segmentIds)
        print(f"Found {len(segmentIds)} segments: {result['segment_names']}")
        
        # Find reference volume
        volumeNodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
        referenceVolume = None
        for vn in volumeNodes:
            if "MRHead" in vn.GetName() or "mr" in vn.GetName().lower():
                referenceVolume = vn
                break
        if not referenceVolume and volumeNodes:
            referenceVolume = volumeNodes[0]
        
        if referenceVolume:
            dims = referenceVolume.GetImageData().GetDimensions()
            result["total_volume_voxels"] = dims[0] * dims[1] * dims[2]
            print(f"Reference volume dimensions: {dims}")
        
        # Export to labelmap to count voxels per segment
        labelmapNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
        
        # Get voxel counts for each segment
        brain_mask = None
        inverse_mask = None
        
        for segId in segmentIds:
            segment = segmentation.GetSegment(segId)
            segName = segment.GetName().lower()
            
            # Export single segment
            segmentIdsToExport = vtk.vtkStringArray()
            segmentIdsToExport.InsertNextValue(segId)
            
            slicer.modules.segmentations.logic().ExportSegmentsToLabelmapNode(
                segNode, segmentIdsToExport, labelmapNode, referenceVolume)
            
            labelArray = slicer.util.arrayFromVolume(labelmapNode)
            voxel_count = int(np.sum(labelArray > 0))
            
            result["segment_voxels"][segment.GetName()] = voxel_count
            print(f"  Segment '{segment.GetName()}': {voxel_count} voxels")
            
            # Identify brain and inverse segments
            if "brain" in segName and "non" not in segName:
                result["brain_segment_found"] = True
                result["brain_voxels"] = voxel_count
                brain_mask = (labelArray > 0).copy()
            
            # Check for inverse/nonbrain segment
            inverse_keywords = ["nonbrain", "non-brain", "non_brain", "inverse", 
                              "background", "skull", "exterior", "complement"]
            if any(kw in segName.replace(" ", "").lower() for kw in inverse_keywords):
                result["inverse_segment_found"] = True
                result["inverse_segment_name"] = segment.GetName()
                result["inverse_voxels"] = voxel_count
                inverse_mask = (labelArray > 0).copy()
        
        # If no explicit inverse found, check if there's a second segment
        if not result["inverse_segment_found"] and result["total_segments"] >= 2:
            for segId in segmentIds:
                segment = segmentation.GetSegment(segId)
                segName = segment.GetName().lower()
                if "brain" not in segName or "non" in segName:
                    # This might be the inverse
                    voxels = result["segment_voxels"].get(segment.GetName(), 0)
                    if voxels > result["brain_voxels"] * 0.5:  # Inverse should be substantial
                        result["inverse_segment_found"] = True
                        result["inverse_segment_name"] = segment.GetName()
                        result["inverse_voxels"] = voxels
                        
                        # Get mask for overlap calculation
                        segmentIdsToExport = vtk.vtkStringArray()
                        segmentIdsToExport.InsertNextValue(segId)
                        slicer.modules.segmentations.logic().ExportSegmentsToLabelmapNode(
                            segNode, segmentIdsToExport, labelmapNode, referenceVolume)
                        labelArray = slicer.util.arrayFromVolume(labelmapNode)
                        inverse_mask = (labelArray > 0).copy()
                        break
        
        # Calculate overlap if both masks exist
        if brain_mask is not None and inverse_mask is not None:
            overlap = brain_mask & inverse_mask
            result["overlap_voxels"] = int(np.sum(overlap))
            if result["brain_voxels"] > 0:
                result["overlap_ratio"] = result["overlap_voxels"] / result["brain_voxels"]
            
            # Calculate coverage
            combined = brain_mask | inverse_mask
            combined_voxels = int(np.sum(combined))
            if result["total_volume_voxels"] > 0:
                result["coverage_ratio"] = combined_voxels / result["total_volume_voxels"]
        
        # Clean up
        slicer.mrmlScene.RemoveNode(labelmapNode)
        
        print(f"Brain voxels: {result['brain_voxels']}")
        print(f"Inverse voxels: {result['inverse_voxels']}")
        print(f"Overlap voxels: {result['overlap_voxels']}")
        print(f"Coverage ratio: {result['coverage_ratio']:.4f}")
        print(f"Overlap ratio: {result['overlap_ratio']:.4f}")

except Exception as e:
    result["error"] = str(e)
    print(f"ERROR: {e}")
    import traceback
    traceback.print_exc()

# Save result
output_path = "/tmp/invert_mask_result.json"
with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"Result saved to {output_path}")
PYEOF

chmod 644 "$EXPORT_SCRIPT"
chown ga:ga "$EXPORT_SCRIPT"

# Run export script in Slicer
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Running export script in Slicer..."
    
    # Use Slicer's Python to run export
    su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-splash --no-main-window --python-script '$EXPORT_SCRIPT'" > /tmp/slicer_export.log 2>&1 &
    EXPORT_PID=$!
    
    # Wait for export to complete (with timeout)
    for i in {1..30}; do
        if [ -f /tmp/invert_mask_result.json ]; then
            echo "Export completed"
            break
        fi
        sleep 2
    done
    
    # Kill export process if still running
    kill $EXPORT_PID 2>/dev/null || true
fi

# Check if result was created
if [ ! -f /tmp/invert_mask_result.json ]; then
    echo "WARNING: Export script did not produce result file"
    
    # Create minimal result
    TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
    cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "export_timestamp": $TASK_END,
    "error": "Export script failed or timed out",
    "segments": [],
    "segment_names": [],
    "total_segments": 0,
    "brain_segment_found": false,
    "inverse_segment_found": false,
    "brain_voxels": 0,
    "inverse_voxels": 0,
    "overlap_voxels": 0,
    "total_volume_voxels": 0,
    "coverage_ratio": 0,
    "overlap_ratio": 0
}
EOF
    mv "$TEMP_JSON" /tmp/invert_mask_result.json
fi

# Add task timing info to result
python3 << PYEOF
import json

try:
    with open('/tmp/invert_mask_result.json', 'r') as f:
        result = json.load(f)
except:
    result = {}

result['task_start_time'] = $TASK_START
result['task_end_time'] = $TASK_END
result['task_duration_sec'] = $TASK_END - $TASK_START
result['final_screenshot_path'] = '/tmp/task_final.png'

# Load initial state for comparison
try:
    with open('/tmp/initial_segmentation_state.json', 'r') as f:
        initial = json.load(f)
    result['initial_brain_voxels'] = initial.get('brain_voxels', 0)
    result['initial_segment_count'] = initial.get('segments_count', 0)
    result['initial_total_voxels'] = initial.get('total_voxels', 0)
except:
    pass

with open('/tmp/invert_mask_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Updated result with timing info")
PYEOF

# Set permissions
chmod 666 /tmp/invert_mask_result.json 2>/dev/null || true

echo ""
echo "=== Export Result ==="
cat /tmp/invert_mask_result.json
echo ""
echo "=== Export Complete ==="