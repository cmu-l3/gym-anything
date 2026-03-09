#!/bin/bash
echo "=== Exporting Locate Anterior Commissure Task Results ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/task_result.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"

# Get task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_DURATION=$((TASK_END - TASK_START))

echo "Task duration: ${TASK_DURATION} seconds"

# Take final screenshot
mkdir -p "$SCREENSHOT_DIR"
FINAL_SCREENSHOT="$SCREENSHOT_DIR/ac_task_final_$(date +%s).png"
take_screenshot "$FINAL_SCREENSHOT" ga
sleep 1

# Also take a standard location screenshot
take_screenshot /tmp/task_final_state.png ga

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "3D Slicer is running"
else
    echo "WARNING: 3D Slicer is not running"
fi

# Query Slicer for fiducial data using Python script
echo "Querying Slicer for fiducial markers..."

FIDUCIAL_QUERY_SCRIPT="/tmp/query_fiducials.py"
cat > "$FIDUCIAL_QUERY_SCRIPT" << 'PYEOF'
import json
import sys
import os

try:
    import slicer
except ImportError:
    print('{"error": "slicer module not available", "fiducials_found": false, "fiducial_count": 0, "fiducials": [], "volumes_loaded": 0}')
    sys.exit(0)

result = {
    'fiducials_found': False,
    'fiducial_count': 0,
    'fiducials': [],
    'volumes_loaded': 0,
    'volume_names': [],
    'scene_modified': False,
    'error': None
}

try:
    # Count loaded volumes
    volume_nodes = slicer.util.getNodesByClass('vtkMRMLScalarVolumeNode')
    result['volumes_loaded'] = len(volume_nodes)
    result['volume_names'] = [node.GetName() for node in volume_nodes]
    
    # Find all markup fiducial nodes (point lists)
    fiducial_nodes = slicer.util.getNodesByClass('vtkMRMLMarkupsFiducialNode')
    
    # Also check for newer point list nodes
    point_nodes = slicer.util.getNodesByClass('vtkMRMLMarkupsPointListNode') if hasattr(slicer.util, 'getNodesByClass') else []
    
    all_nodes = list(fiducial_nodes) + list(point_nodes)
    
    result['fiducial_count'] = len(all_nodes)
    
    if all_nodes:
        result['fiducials_found'] = True
        
        for node in all_nodes:
            n_points = node.GetNumberOfControlPoints()
            
            for i in range(n_points):
                pos = [0.0, 0.0, 0.0]
                node.GetNthControlPointPosition(i, pos)
                
                fiducial_info = {
                    'name': node.GetNthControlPointLabel(i),
                    'position_ras': pos,
                    'node_name': node.GetName(),
                    'node_id': node.GetID(),
                    'point_index': i,
                    'r_coord': pos[0],
                    'a_coord': pos[1],
                    's_coord': pos[2]
                }
                result['fiducials'].append(fiducial_info)
    
    # Check if scene has been modified
    result['scene_modified'] = slicer.mrmlScene.GetModifiedSinceRead()
    
except Exception as e:
    result['error'] = str(e)

# Output JSON
print(json.dumps(result))
PYEOF

# Execute query script in Slicer
FIDUCIAL_DATA=""
if [ "$SLICER_RUNNING" = "true" ]; then
    # Run the Python script in Slicer context
    FIDUCIAL_DATA=$(sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --no-main-window --python-script "$FIDUCIAL_QUERY_SCRIPT" 2>/dev/null | grep -E '^\{.*\}$' | tail -1)
    
    # If that didn't work, try alternative approach
    if [ -z "$FIDUCIAL_DATA" ] || [ "$FIDUCIAL_DATA" = "{}" ]; then
        echo "Trying alternative query method..."
        FIDUCIAL_DATA=$(sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-code "
import json
import slicer

result = {'fiducials_found': False, 'fiducial_count': 0, 'fiducials': [], 'volumes_loaded': 0}

try:
    result['volumes_loaded'] = slicer.mrmlScene.GetNumberOfNodesByClass('vtkMRMLScalarVolumeNode')
    
    fiducial_nodes = slicer.util.getNodesByClass('vtkMRMLMarkupsFiducialNode')
    result['fiducial_count'] = len(fiducial_nodes)
    
    if fiducial_nodes:
        result['fiducials_found'] = True
        for node in fiducial_nodes:
            for i in range(node.GetNumberOfControlPoints()):
                pos = [0.0, 0.0, 0.0]
                node.GetNthControlPointPosition(i, pos)
                result['fiducials'].append({
                    'name': node.GetNthControlPointLabel(i),
                    'position_ras': pos,
                    'node_name': node.GetName()
                })
except Exception as e:
    result['error'] = str(e)

print(json.dumps(result))
exit()
" 2>/dev/null | grep -E '^\{.*\}$' | tail -1)
    fi
fi

# Default result if query failed
if [ -z "$FIDUCIAL_DATA" ]; then
    echo "WARNING: Could not query Slicer for fiducial data"
    FIDUCIAL_DATA='{"fiducials_found": false, "fiducial_count": 0, "fiducials": [], "volumes_loaded": 0, "error": "query_failed"}'
fi

echo "Fiducial query result: $FIDUCIAL_DATA"

# Load ground truth
GT_FILE="$GROUND_TRUTH_DIR/mrhead_landmarks.json"
GT_AC_COORDS="[0.0, 1.5, -3.0]"
if [ -f "$GT_FILE" ]; then
    GT_AC_COORDS=$(python3 -c "
import json
with open('$GT_FILE') as f:
    gt = json.load(f)
print(json.dumps(gt['landmarks']['anterior_commissure']['coordinates_ras']))
" 2>/dev/null || echo "[0.0, 1.5, -3.0]")
fi

# Calculate distances and create validation result
VALIDATION_RESULT=$(python3 << PYEOF
import json
import math

fiducial_data_str = '''$FIDUCIAL_DATA'''
gt_ac = $GT_AC_COORDS
task_start = $TASK_START
task_end = $TASK_END

try:
    fiducial_data = json.loads(fiducial_data_str)
except:
    fiducial_data = {'fiducials_found': False, 'fiducial_count': 0, 'fiducials': [], 'volumes_loaded': 0}

result = {
    'slicer_running': $( [ "$SLICER_RUNNING" = "true" ] && echo "true" || echo "false" ),
    'volumes_loaded': fiducial_data.get('volumes_loaded', 0),
    'fiducials_found': fiducial_data.get('fiducials_found', False),
    'fiducial_count': fiducial_data.get('fiducial_count', 0),
    'fiducials': fiducial_data.get('fiducials', []),
    'ground_truth_ac': gt_ac,
    'closest_distance_mm': -1,
    'closest_fiducial': None,
    'within_5mm': False,
    'within_3mm': False,
    'midline_placement': False,
    'task_start_time': task_start,
    'task_end_time': task_end,
    'task_duration_sec': task_end - task_start,
    'screenshot_path': '$FINAL_SCREENSHOT',
    'query_error': fiducial_data.get('error', None)
}

# Find closest fiducial to AC
min_dist = float('inf')
for fid in result['fiducials']:
    pos = fid.get('position_ras', [0, 0, 0])
    if pos and len(pos) >= 3:
        dist = math.sqrt(sum((a - b)**2 for a, b in zip(pos, gt_ac)))
        if dist < min_dist:
            min_dist = dist
            result['closest_distance_mm'] = round(dist, 2)
            result['closest_fiducial'] = fid

# Evaluate accuracy
if min_dist != float('inf'):
    result['within_5mm'] = min_dist <= 5.0
    result['within_3mm'] = min_dist <= 3.0
    
    # Check midline (R coordinate should be near 0)
    if result['closest_fiducial']:
        r_coord = result['closest_fiducial'].get('position_ras', [999])[0]
        result['midline_placement'] = abs(r_coord) <= 2.0
        result['r_coordinate'] = round(r_coord, 2)

print(json.dumps(result, indent=2))
PYEOF
)

# Save result to file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
echo "$VALIDATION_RESULT" > "$TEMP_JSON"

# Move to final location with proper permissions
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Results Exported ==="
cat "$RESULT_FILE"
echo ""

# Clean up
rm -f "$FIDUCIAL_QUERY_SCRIPT" 2>/dev/null || true

echo "=== Export Complete ==="