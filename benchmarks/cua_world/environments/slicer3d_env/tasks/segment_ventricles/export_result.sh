#!/bin/bash
echo "=== Exporting Segment Ventricles Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ELAPSED=$((TASK_END - TASK_START))
echo "Task duration: ${ELAPSED} seconds"

# Take final screenshot (evidence of final state)
echo "Capturing final state screenshot..."
take_screenshot /tmp/task_final_state.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
SLICER_PID=""
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    SLICER_PID=$(pgrep -f "Slicer" | head -1)
    echo "Slicer is running (PID: $SLICER_PID)"
else
    echo "Warning: Slicer is not running"
fi

# Define paths
OUTPUT_DIR="/home/ga/Documents/SlicerData/Exports"
MEASUREMENT_FILE="$OUTPUT_DIR/ventricle_measurement.json"

# Check measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_CREATED_DURING_TASK="false"
VOLUME_ML="0"
SEGMENT_NAME=""

if [ -f "$MEASUREMENT_FILE" ]; then
    MEASUREMENT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$MEASUREMENT_FILE" 2>/dev/null || echo "0")
    
    # Check if file was created during task (anti-gaming)
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        MEASUREMENT_CREATED_DURING_TASK="true"
        echo "Measurement file created during task"
    else
        echo "Warning: Measurement file existed before task started"
    fi
    
    # Parse the measurement file
    VOLUME_ML=$(python3 -c "
import json
try:
    with open('$MEASUREMENT_FILE', 'r') as f:
        data = json.load(f)
    vol = data.get('volume_ml', data.get('volume', data.get('Volume_ml', 0)))
    print(float(vol))
except Exception as e:
    print(0)
" 2>/dev/null || echo "0")
    
    SEGMENT_NAME=$(python3 -c "
import json
try:
    with open('$MEASUREMENT_FILE', 'r') as f:
        data = json.load(f)
    print(data.get('segment_name', ''))
except:
    print('')
" 2>/dev/null || echo "")
    
    echo "Measurement file found:"
    echo "  Volume: $VOLUME_ML mL"
    echo "  Segment name: $SEGMENT_NAME"
else
    echo "Measurement file NOT found at $MEASUREMENT_FILE"
fi

# Try to query Slicer for segmentation state
SEGMENTATION_EXISTS="false"
SLICER_SEGMENT_NAME=""
SLICER_SEGMENT_VOXELS="0"
SLICER_SEGMENT_VOLUME_ML="0"

if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Querying Slicer for segmentation state..."
    
    # Create Python script to query Slicer
    cat > /tmp/query_ventricle_seg.py << 'PYEOF'
import json
import sys
import os

result = {
    "segmentation_exists": False,
    "segment_name": "",
    "segment_voxels": 0,
    "segment_volume_ml": 0,
    "error": None
}

try:
    import slicer
    
    # Find segmentation nodes
    seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
    
    for seg_node in seg_nodes:
        segmentation = seg_node.GetSegmentation()
        num_segments = segmentation.GetNumberOfSegments()
        
        for i in range(num_segments):
            segment_id = segmentation.GetNthSegmentID(i)
            segment = segmentation.GetSegment(segment_id)
            segment_name = segment.GetName().lower()
            
            # Check if this is a ventricle segment
            if any(keyword in segment_name for keyword in ["ventricle", "vent", "csf", "lateral"]):
                result["segmentation_exists"] = True
                result["segment_name"] = segment.GetName()
                
                # Try to get volume from segment statistics
                try:
                    import SegmentStatistics
                    stats_logic = SegmentStatistics.SegmentStatisticsLogic()
                    stats_logic.getParameterNode().SetParameter("Segmentation", seg_node.GetID())
                    stats_logic.computeStatistics()
                    stats = stats_logic.getStatistics()
                    
                    volume_key = f"{segment_id},LabelmapSegmentStatisticsPlugin.volume_mm3"
                    voxel_key = f"{segment_id},LabelmapSegmentStatisticsPlugin.voxel_count"
                    
                    if volume_key in stats:
                        volume_mm3 = stats[volume_key]
                        result["segment_volume_ml"] = volume_mm3 / 1000.0
                    if voxel_key in stats:
                        result["segment_voxels"] = int(stats[voxel_key])
                except Exception as e:
                    result["stats_error"] = str(e)
                
                break
        
        if result["segmentation_exists"]:
            break
    
except Exception as e:
    result["error"] = str(e)

# Output JSON to file
with open("/tmp/slicer_seg_query_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result))
PYEOF

    # Run query script in Slicer
    timeout 30 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --no-main-window \
        --python-script /tmp/query_ventricle_seg.py > /tmp/slicer_query.log 2>&1 || true
    
    # Read result if available
    if [ -f /tmp/slicer_seg_query_result.json ]; then
        SEGMENTATION_EXISTS=$(python3 -c "
import json
try:
    with open('/tmp/slicer_seg_query_result.json') as f:
        data = json.load(f)
    print('true' if data.get('segmentation_exists') else 'false')
except:
    print('false')
" 2>/dev/null || echo "false")
        
        SLICER_SEGMENT_NAME=$(python3 -c "
import json
try:
    with open('/tmp/slicer_seg_query_result.json') as f:
        data = json.load(f)
    print(data.get('segment_name', ''))
except:
    print('')
" 2>/dev/null || echo "")
        
        SLICER_SEGMENT_VOXELS=$(python3 -c "
import json
try:
    with open('/tmp/slicer_seg_query_result.json') as f:
        data = json.load(f)
    print(int(data.get('segment_voxels', 0)))
except:
    print(0)
" 2>/dev/null || echo "0")
        
        SLICER_SEGMENT_VOLUME_ML=$(python3 -c "
import json
try:
    with open('/tmp/slicer_seg_query_result.json') as f:
        data = json.load(f)
    print(float(data.get('segment_volume_ml', 0)))
except:
    print(0)
" 2>/dev/null || echo "0")
        
        echo "Slicer query results:"
        echo "  Segmentation exists: $SEGMENTATION_EXISTS"
        echo "  Segment name: $SLICER_SEGMENT_NAME"
        echo "  Segment voxels: $SLICER_SEGMENT_VOXELS"
        echo "  Segment volume: $SLICER_SEGMENT_VOLUME_ML mL"
    fi
fi

# Check for any segmentation files that may have been saved
SAVED_SEG_FILES=$(find "$OUTPUT_DIR" -name "*.seg.nrrd" -o -name "*segmentation*.nrrd" 2>/dev/null | head -3)
SAVED_SEG_COUNT=$(echo "$SAVED_SEG_FILES" | grep -c "." 2>/dev/null || echo "0")

# Verify screenshot exists
FINAL_SCREENSHOT_EXISTS="false"
FINAL_SCREENSHOT_SIZE="0"
if [ -f /tmp/task_final_state.png ]; then
    FINAL_SCREENSHOT_EXISTS="true"
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
fi

# Create result JSON
RESULT_FILE="/tmp/task_result.json"
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_id": "segment_ventricles@1",
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "elapsed_seconds": $ELAPSED,
    "slicer_running": $SLICER_RUNNING,
    "measurement_file_exists": $MEASUREMENT_EXISTS,
    "measurement_created_during_task": $MEASUREMENT_CREATED_DURING_TASK,
    "measurement_file_path": "$MEASUREMENT_FILE",
    "reported_volume_ml": $VOLUME_ML,
    "reported_segment_name": "$SEGMENT_NAME",
    "segmentation_exists": $SEGMENTATION_EXISTS,
    "slicer_segment_name": "$SLICER_SEGMENT_NAME",
    "slicer_segment_voxels": $SLICER_SEGMENT_VOXELS,
    "slicer_segment_volume_ml": $SLICER_SEGMENT_VOLUME_ML,
    "saved_segmentation_files": $SAVED_SEG_COUNT,
    "final_screenshot_exists": $FINAL_SCREENSHOT_EXISTS,
    "final_screenshot_size": $FINAL_SCREENSHOT_SIZE,
    "initial_screenshot": "/tmp/task_initial_state.png",
    "final_screenshot": "/tmp/task_final_state.png"
}
EOF

# Move to final location with permission handling
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Result saved to: $RESULT_FILE"
cat "$RESULT_FILE"
echo ""