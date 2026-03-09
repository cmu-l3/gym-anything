#!/bin/bash
echo "=== Exporting Split Segment Scissors Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get patient info
PATIENT_NUM=$(cat /tmp/ircadb_patient_num 2>/dev/null || echo "5")
IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final state screenshot..."
take_screenshot /tmp/task_final_screenshot.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Create Python script to extract segmentation state from Slicer
EXPORT_SCRIPT="/tmp/export_scissors_state.py"
cat > "$EXPORT_SCRIPT" << 'PYEOF'
import slicer
import json
import os
import math
from datetime import datetime

result = {
    "timestamp": datetime.now().isoformat(),
    "slicer_running": True,
    "segmentation_found": False,
    "segment_count": 0,
    "liver_segment_count": 0,
    "segments": [],
    "total_liver_volume_cm3": 0,
    "original_liver_volume_cm3": 0,
    "volume_conservation_ratio": 0,
    "split_ratio": 0,
    "overlap_fraction": 0,
    "same_level": True,
    "task_completed": False
}

gt_dir = os.environ.get("GROUND_TRUTH_DIR", "/var/lib/slicer/ground_truth")
patient_num = os.environ.get("PATIENT_NUM", "5")

# Load original stats for comparison
original_stats_file = os.path.join(gt_dir, "scissors_task_original_stats.json")
if os.path.exists(original_stats_file):
    with open(original_stats_file, 'r') as f:
        original_stats = json.load(f)
    
    # Get original volume
    for seg_id, seg_info in original_stats.get("segments", {}).items():
        if "liver" in seg_info.get("name", "").lower():
            result["original_liver_volume_cm3"] += seg_info.get("volume_cm3", 0)
    
    # Also check alternative formats
    if result["original_liver_volume_cm3"] == 0:
        result["original_liver_volume_cm3"] = original_stats.get("original_liver_volume_ml", 0)
    
    print(f"Original liver volume: {result['original_liver_volume_cm3']:.2f} cm³")

# Find segmentation node
segNodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
if not segNodes:
    print("No segmentation nodes found")
else:
    segNode = segNodes[0]
    result["segmentation_found"] = True
    
    segmentation = segNode.GetSegmentation()
    result["segment_count"] = segmentation.GetNumberOfSegments()
    print(f"Found {result['segment_count']} segment(s)")
    
    # Get segment statistics
    import SegmentStatistics
    segStatLogic = SegmentStatistics.SegmentStatisticsLogic()
    segStatLogic.getParameterNode().SetParameter("Segmentation", segNode.GetID())
    
    volumeNodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    if volumeNodes:
        segStatLogic.getParameterNode().SetParameter("ScalarVolume", volumeNodes[0].GetID())
    
    segStatLogic.computeStatistics()
    stats = segStatLogic.getStatistics()
    
    liver_volumes = []
    all_segments = []
    
    for segmentId in stats.get("SegmentIDs", []):
        segment = segmentation.GetSegment(segmentId)
        segName = segment.GetName() if segment else segmentId
        
        volume_key = f"{segmentId}.LabelmapSegmentStatisticsPlugin.volume_cm3"
        volume_cm3 = stats.get(volume_key, 0)
        
        # Get segment bounds for overlap check
        bounds = [0]*6
        segmentation.GetSegmentBounds(segmentId, bounds)
        
        seg_info = {
            "id": segmentId,
            "name": segName,
            "volume_cm3": volume_cm3,
            "bounds_z": [bounds[4], bounds[5]] if bounds[5] > bounds[4] else [0, 0]
        }
        all_segments.append(seg_info)
        
        # Check if this is a liver segment
        name_lower = segName.lower()
        if "liver" in name_lower or "hepat" in name_lower:
            liver_volumes.append(volume_cm3)
            result["liver_segment_count"] += 1
            result["total_liver_volume_cm3"] += volume_cm3
            print(f"  Liver segment '{segName}': {volume_cm3:.2f} cm³")
        else:
            print(f"  Other segment '{segName}': {volume_cm3:.2f} cm³")
    
    result["segments"] = all_segments
    
    # Calculate volume conservation ratio
    if result["original_liver_volume_cm3"] > 0:
        result["volume_conservation_ratio"] = result["total_liver_volume_cm3"] / result["original_liver_volume_cm3"]
        print(f"Volume conservation: {result['volume_conservation_ratio']*100:.1f}%")
    
    # Calculate split ratio (smaller / total)
    if len(liver_volumes) >= 2:
        liver_volumes_sorted = sorted(liver_volumes, reverse=True)
        total_two = liver_volumes_sorted[0] + liver_volumes_sorted[1]
        if total_two > 0:
            smaller_vol = liver_volumes_sorted[1]
            result["split_ratio"] = smaller_vol / total_two
            print(f"Split ratio: {result['split_ratio']*100:.1f}% / {(1-result['split_ratio'])*100:.1f}%")
    
    # Simple overlap detection based on volume conservation
    # If conservation > 1.1, likely overlap
    if result["volume_conservation_ratio"] > 1.1:
        result["overlap_fraction"] = result["volume_conservation_ratio"] - 1.0
        print(f"Possible overlap detected: {result['overlap_fraction']*100:.1f}%")
    
    # Check if task is complete
    # Need: 2+ liver segments, reasonable split (20-80%), good conservation (80-120%)
    if (result["liver_segment_count"] >= 2 and
        0.15 <= result["split_ratio"] <= 0.85 and
        0.75 <= result["volume_conservation_ratio"] <= 1.25):
        result["task_completed"] = True
        print("Task appears COMPLETE")
    else:
        print("Task NOT complete:")
        if result["liver_segment_count"] < 2:
            print(f"  - Need 2+ liver segments, have {result['liver_segment_count']}")
        if not (0.15 <= result["split_ratio"] <= 0.85):
            print(f"  - Split ratio {result['split_ratio']:.2f} outside 0.15-0.85")
        if not (0.75 <= result["volume_conservation_ratio"] <= 1.25):
            print(f"  - Conservation {result['volume_conservation_ratio']:.2f} outside 0.75-1.25")

# Save result
output_file = "/tmp/scissors_task_result.json"
with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f"\nResult saved to {output_file}")
PYEOF

chmod 644 "$EXPORT_SCRIPT"

# Run export script if Slicer is running
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Extracting segmentation state from Slicer..."
    export GROUND_TRUTH_DIR PATIENT_NUM
    
    # Run script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script "$EXPORT_SCRIPT" --no-main-window > /tmp/export_log.txt 2>&1 &
    EXPORT_PID=$!
    
    # Wait with timeout
    for i in {1..30}; do
        if [ -f /tmp/scissors_task_result.json ]; then
            echo "Export complete"
            break
        fi
        sleep 1
    done
    
    # Kill export process if still running
    kill $EXPORT_PID 2>/dev/null || true
    sleep 2
fi

# If result file doesn't exist, create a failure result
if [ ! -f /tmp/scissors_task_result.json ]; then
    echo "Creating fallback result (export may have failed)..."
    cat > /tmp/scissors_task_result.json << EOF
{
    "timestamp": "$(date -Iseconds)",
    "slicer_running": $SLICER_RUNNING,
    "segmentation_found": false,
    "segment_count": 0,
    "liver_segment_count": 0,
    "segments": [],
    "total_liver_volume_cm3": 0,
    "original_liver_volume_cm3": 0,
    "volume_conservation_ratio": 0,
    "split_ratio": 0,
    "overlap_fraction": 0,
    "task_completed": false,
    "error": "Could not extract segmentation state from Slicer"
}
EOF
fi

# Add timing information to result
python3 << PYEOF
import json

try:
    with open('/tmp/scissors_task_result.json', 'r') as f:
        result = json.load(f)
except:
    result = {}

result['task_start_time'] = $TASK_START
result['task_end_time'] = $TASK_END
result['task_duration_seconds'] = $TASK_END - $TASK_START
result['screenshot_path'] = '/tmp/task_final_screenshot.png'

with open('/tmp/scissors_task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Set permissions
chmod 666 /tmp/scissors_task_result.json 2>/dev/null || true
chmod 666 /tmp/task_final_screenshot.png 2>/dev/null || true

echo ""
echo "=== Export Complete ==="
echo "Result file: /tmp/scissors_task_result.json"
cat /tmp/scissors_task_result.json