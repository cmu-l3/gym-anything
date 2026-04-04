#!/bin/bash
echo "=== Exporting Slab MIP Configuration Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    FINAL_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SIZE} bytes"
fi

# Check if Slicer is running
SLICER_RUNNING="false"
SLICER_PID=""
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    SLICER_PID=$(pgrep -f "Slicer" | head -1)
    echo "Slicer is running (PID: $SLICER_PID)"
fi

# Query Slicer for current slab configuration
echo "Querying Slicer for slab configuration..."

cat > /tmp/export_slab_config.py << 'PYEOF'
import slicer
import json
import os

result = {
    'slicer_running': True,
    'slab_mode': -1,
    'slab_mode_name': 'Unknown',
    'slab_slices': 0,
    'slab_thickness_mm': 0.0,
    'volume_spacing_z': 1.0,
    'slice_view': 'Red',
    'volume_loaded': False,
    'error': None
}

try:
    # Get axial (Red) slice node
    sliceNode = slicer.mrmlScene.GetNodeByID('vtkMRMLSliceNodeRed')
    
    if sliceNode:
        result['slab_mode'] = sliceNode.GetSlabMode()
        
        # Map mode number to name
        mode_names = {0: 'None', 1: 'Min', 2: 'Max', 3: 'Mean', 4: 'Sum'}
        result['slab_mode_name'] = mode_names.get(result['slab_mode'], 'Unknown')
        
        result['slab_slices'] = sliceNode.GetSlabNumberOfSlices()
    else:
        result['error'] = 'Could not find Red slice node'
    
    # Get volume spacing for thickness calculation
    volumeNode = slicer.mrmlScene.GetFirstNodeByClass('vtkMRMLScalarVolumeNode')
    if volumeNode:
        result['volume_loaded'] = True
        spacing = volumeNode.GetSpacing()
        result['volume_spacing_z'] = float(spacing[2])
        result['slab_thickness_mm'] = float(result['slab_slices']) * float(spacing[2])
    else:
        result['volume_loaded'] = False
        # Estimate thickness assuming 2.5mm slices (common for abdominal CT)
        result['volume_spacing_z'] = 2.5
        result['slab_thickness_mm'] = float(result['slab_slices']) * 2.5
    
    # Also check Green and Yellow slice nodes for comparison
    for view_name, node_id in [('Green', 'vtkMRMLSliceNodeGreen'), ('Yellow', 'vtkMRMLSliceNodeYellow')]:
        node = slicer.mrmlScene.GetNodeByID(node_id)
        if node:
            result[f'{view_name.lower()}_slab_mode'] = node.GetSlabMode()
            result[f'{view_name.lower()}_slab_slices'] = node.GetSlabNumberOfSlices()

except Exception as e:
    result['error'] = str(e)

# Save result
with open('/tmp/slab_config.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Run the export script
if [ "$SLICER_RUNNING" = "true" ]; then
    DISPLAY=:1 /opt/Slicer/Slicer --no-main-window --python-script /tmp/export_slab_config.py > /tmp/slicer_export.log 2>&1 &
    EXPORT_PID=$!
    sleep 15
    kill $EXPORT_PID 2>/dev/null || true
fi

# Read the configuration results
SLAB_MODE=-1
SLAB_MODE_NAME="Unknown"
SLAB_SLICES=0
SLAB_THICKNESS_MM=0
VOLUME_LOADED="false"
CONFIG_ERROR=""

if [ -f /tmp/slab_config.json ]; then
    echo "Slab configuration exported:"
    cat /tmp/slab_config.json
    
    SLAB_MODE=$(python3 -c "import json; d=json.load(open('/tmp/slab_config.json')); print(d.get('slab_mode', -1))" 2>/dev/null || echo "-1")
    SLAB_MODE_NAME=$(python3 -c "import json; d=json.load(open('/tmp/slab_config.json')); print(d.get('slab_mode_name', 'Unknown'))" 2>/dev/null || echo "Unknown")
    SLAB_SLICES=$(python3 -c "import json; d=json.load(open('/tmp/slab_config.json')); print(d.get('slab_slices', 0))" 2>/dev/null || echo "0")
    SLAB_THICKNESS_MM=$(python3 -c "import json; d=json.load(open('/tmp/slab_config.json')); print(d.get('slab_thickness_mm', 0))" 2>/dev/null || echo "0")
    VOLUME_LOADED=$(python3 -c "import json; d=json.load(open('/tmp/slab_config.json')); print('true' if d.get('volume_loaded', False) else 'false')" 2>/dev/null || echo "false")
    CONFIG_ERROR=$(python3 -c "import json; d=json.load(open('/tmp/slab_config.json')); e=d.get('error'); print(e if e else '')" 2>/dev/null || echo "")
else
    echo "Warning: Slab config file not found"
    CONFIG_ERROR="Export failed - config file not created"
fi

# Get initial state for comparison
INITIAL_SLAB_MODE=0
INITIAL_SLAB_SLICES=1
if [ -f /tmp/initial_slab_state.json ]; then
    INITIAL_SLAB_MODE=$(python3 -c "import json; d=json.load(open('/tmp/initial_slab_state.json')); print(d.get('slab_mode', 0))" 2>/dev/null || echo "0")
    INITIAL_SLAB_SLICES=$(python3 -c "import json; d=json.load(open('/tmp/initial_slab_state.json')); print(d.get('slab_slices', 1))" 2>/dev/null || echo "1")
fi

# Determine if configuration was changed
CONFIG_CHANGED="false"
if [ "$SLAB_MODE" != "$INITIAL_SLAB_MODE" ] || [ "$SLAB_SLICES" != "$INITIAL_SLAB_SLICES" ]; then
    CONFIG_CHANGED="true"
fi

# Check if configuration is correct
SLAB_MODE_CORRECT="false"
if [ "$SLAB_MODE" = "2" ]; then
    SLAB_MODE_CORRECT="true"
fi

THICKNESS_CORRECT="false"
if [ -n "$SLAB_THICKNESS_MM" ]; then
    # Check if thickness is in range 8-12mm
    THICKNESS_CHECK=$(python3 -c "t=float('$SLAB_THICKNESS_MM'); print('true' if 8.0 <= t <= 12.0 else 'false')" 2>/dev/null || echo "false")
    THICKNESS_CORRECT="$THICKNESS_CHECK"
fi

# Create final result JSON
RESULT_FILE="/tmp/slab_mip_result.json"
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_running": $SLICER_RUNNING,
    "volume_loaded": $VOLUME_LOADED,
    "slab_mode": $SLAB_MODE,
    "slab_mode_name": "$SLAB_MODE_NAME",
    "slab_slices": $SLAB_SLICES,
    "slab_thickness_mm": $SLAB_THICKNESS_MM,
    "initial_slab_mode": $INITIAL_SLAB_MODE,
    "initial_slab_slices": $INITIAL_SLAB_SLICES,
    "config_changed": $CONFIG_CHANGED,
    "slab_mode_correct": $SLAB_MODE_CORRECT,
    "thickness_in_range": $THICKNESS_CORRECT,
    "config_error": "$CONFIG_ERROR",
    "screenshot_initial": "/tmp/task_initial_state.png",
    "screenshot_final": "/tmp/task_final_state.png"
}
EOF

# Move to final location
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Summary ==="
echo "Slicer running: $SLICER_RUNNING"
echo "Volume loaded: $VOLUME_LOADED"
echo "Slab mode: $SLAB_MODE ($SLAB_MODE_NAME)"
echo "Slab thickness: ${SLAB_THICKNESS_MM}mm ($SLAB_SLICES slices)"
echo "Configuration changed: $CONFIG_CHANGED"
echo "Mode correct (Max/MIP): $SLAB_MODE_CORRECT"
echo "Thickness in range (8-12mm): $THICKNESS_CORRECT"
echo ""
echo "Result saved to: $RESULT_FILE"
cat "$RESULT_FILE"
echo ""
echo "=== Export Complete ==="