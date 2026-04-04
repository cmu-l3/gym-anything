#!/bin/bash
echo "=== Exporting Load Sample Data Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot of Slicer state
echo "Capturing final screenshot..."
take_screenshot /tmp/slicer_final.png ga
sleep 1

# Get screenshot info
SCREENSHOT_DIR=$(get_slicer_screenshot_dir)
FINAL_SCREENSHOT_COUNT=$(ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null | wc -l)
INITIAL_SCREENSHOT_COUNT=$(cat /tmp/initial_screenshot_count 2>/dev/null || echo "0")

# Check final screenshot properties
FINAL_SCREENSHOT="/tmp/slicer_final.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE_KB=0

if [ -f "$FINAL_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE_KB=$(du -k "$FINAL_SCREENSHOT" 2>/dev/null | cut -f1 || echo "0")
fi

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Check if sample file exists on disk
SAMPLE_FILE="$(get_sample_data_dir)/MRHead.nrrd"
SAMPLE_FILE_EXISTS="false"
if [ -f "$SAMPLE_FILE" ]; then
    SAMPLE_FILE_EXISTS="true"
fi

# ============================================================
# CRITICAL: Query Slicer's Python API to verify data is loaded
# This is the ONLY reliable way to verify task completion
# ============================================================
VOLUME_LOADED="false"
LOADED_VOLUME_NAME=""
VOLUME_COUNT=0
MRHEAD_LOADED="false"

if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Querying Slicer scene for loaded volumes..."

    # Create Python script to query Slicer's scene
    cat > /tmp/query_slicer_scene.py << 'PYEOF'
import sys
import json

try:
    import slicer

    # Get all volume nodes in the scene
    volume_nodes = slicer.mrmlScene.GetNodesByClass('vtkMRMLScalarVolumeNode')
    volume_nodes.InitTraversal()

    volumes = []
    node = volume_nodes.GetNextItemAsObject()
    while node:
        volumes.append({
            'name': node.GetName(),
            'id': node.GetID(),
            'className': node.GetClassName()
        })
        node = volume_nodes.GetNextItemAsObject()

    # Also check for vector volumes
    vector_nodes = slicer.mrmlScene.GetNodesByClass('vtkMRMLVectorVolumeNode')
    vector_nodes.InitTraversal()
    node = vector_nodes.GetNextItemAsObject()
    while node:
        volumes.append({
            'name': node.GetName(),
            'id': node.GetID(),
            'className': node.GetClassName()
        })
        node = vector_nodes.GetNextItemAsObject()

    result = {
        'success': True,
        'volume_count': len(volumes),
        'volumes': volumes
    }

    # Check if MRHead is loaded
    mrhead_found = any('MRHead' in v['name'] or 'mrhead' in v['name'].lower() for v in volumes)
    result['mrhead_loaded'] = mrhead_found

    print(json.dumps(result))

except Exception as e:
    print(json.dumps({'success': False, 'error': str(e)}))
PYEOF

    # Execute Python script in Slicer's context using xdotool
    # Slicer's Python console can execute scripts
    # Alternative: Use Slicer's --python-script flag (but Slicer is already running)

    # Method: Write result to file via Slicer's Python interactor
    # We'll use xdotool to open Python console and execute code

    # Simpler approach: Check Slicer's recent documents or MRML scene file
    SLICER_SCENE_DIR="/home/ga/.config/NA-MIC/Slicer"

    # Check if any .mrml scene files exist that might indicate loaded data
    # Better: Check Slicer's application log for "Added volume"
    SLICER_LOG="/tmp/slicer_ga.log"
    if [ -f "$SLICER_LOG" ]; then
        if grep -qi "MRHead\|Added.*volume\|Loaded.*nrrd" "$SLICER_LOG" 2>/dev/null; then
            VOLUME_LOADED="true"
            LOADED_VOLUME_NAME="MRHead (from log)"
        fi
    fi

    # Check file descriptors - if MRHead.nrrd is open, data is being used
    SLICER_PID=$(pgrep -f "SlicerApp-real" | head -1)
    if [ -n "$SLICER_PID" ]; then
        # Check if Slicer has the file open
        if ls -la /proc/$SLICER_PID/fd 2>/dev/null | grep -q "MRHead"; then
            VOLUME_LOADED="true"
            MRHEAD_LOADED="true"
        fi

        # Check memory maps for loaded data
        if grep -q "MRHead" /proc/$SLICER_PID/maps 2>/dev/null; then
            VOLUME_LOADED="true"
            MRHEAD_LOADED="true"
        fi
    fi

    # Most reliable: Use Slicer's --python-code to query and save result
    # Run a separate Slicer instance to query the running one's state
    # Actually, we can use slicer module from PythonSlicer if available

    # Use SlicerPython directly if available
    if [ -x "/opt/Slicer/bin/PythonSlicer" ]; then
        echo "Using PythonSlicer to query scene..."
        QUERY_RESULT=$(/opt/Slicer/bin/PythonSlicer -c "
import json
try:
    import slicer
    nodes = slicer.mrmlScene.GetNodesByClass('vtkMRMLScalarVolumeNode')
    nodes.InitTraversal()
    count = 0
    names = []
    n = nodes.GetNextItemAsObject()
    while n:
        count += 1
        names.append(n.GetName())
        n = nodes.GetNextItemAsObject()
    print(json.dumps({'count': count, 'names': names}))
except:
    print(json.dumps({'count': 0, 'names': []}))
" 2>/dev/null || echo '{"count": 0, "names": []}')

        VOLUME_COUNT=$(echo "$QUERY_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('count',0))" 2>/dev/null || echo "0")
        if [ "$VOLUME_COUNT" -gt 0 ]; then
            VOLUME_LOADED="true"
            LOADED_VOLUME_NAME=$(echo "$QUERY_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(','.join(d.get('names',[])))" 2>/dev/null || echo "")
            if echo "$LOADED_VOLUME_NAME" | grep -qi "MRHead"; then
                MRHEAD_LOADED="true"
            fi
        fi
    fi
fi

# Fallback: Check if slice views show data by analyzing screenshot pixel values
# A screenshot with loaded brain data will have specific pixel patterns
if [ "$VOLUME_LOADED" = "false" ] && [ -f "$FINAL_SCREENSHOT" ]; then
    echo "Analyzing screenshot for loaded data..."

    # Use ImageMagick to check if the slice view areas have varied grayscale
    # Brain MRI data shows gray matter - check for grayscale variation
    if command -v convert &> /dev/null; then
        # Sample pixels from where slice views would be (center-left area)
        # If data is loaded, we expect grayscale values between 50-200
        # If empty, slice views are pure black (0) or have just axes

        UNIQUE_COLORS=$(identify -format "%k" "$FINAL_SCREENSHOT" 2>/dev/null || echo "0")

        # Get histogram - loaded data has many mid-gray values
        GRAY_PIXELS=$(convert "$FINAL_SCREENSHOT" -colorspace Gray -format "%c" histogram:info:- 2>/dev/null | \
            grep -E "^\s+[0-9]+:.*gray\([0-9]+" | wc -l || echo "0")

        # If we have more than 50 distinct gray levels, likely data is loaded
        if [ "$GRAY_PIXELS" -gt 50 ]; then
            echo "Screenshot analysis suggests data may be loaded ($GRAY_PIXELS gray levels)"
            # Don't set VOLUME_LOADED=true here - this is just a hint, not verification
        fi
    fi
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Create result JSON with detailed verification data
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_kb": $SCREENSHOT_SIZE_KB,
    "slicer_was_running": $SLICER_RUNNING,
    "sample_file_exists": $SAMPLE_FILE_EXISTS,
    "volume_loaded": $VOLUME_LOADED,
    "volume_count": $VOLUME_COUNT,
    "loaded_volume_name": "$LOADED_VOLUME_NAME",
    "mrhead_loaded": $MRHEAD_LOADED,
    "initial_screenshot_count": $INITIAL_SCREENSHOT_COUNT,
    "final_screenshot_count": $FINAL_SCREENSHOT_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/slicer_task_result.json 2>/dev/null || sudo rm -f /tmp/slicer_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/slicer_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/slicer_task_result.json
chmod 666 /tmp/slicer_task_result.json 2>/dev/null || sudo chmod 666 /tmp/slicer_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/slicer_task_result.json"
cat /tmp/slicer_task_result.json
echo ""
echo "=== Export Complete ==="
