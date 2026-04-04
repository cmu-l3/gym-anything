#!/bin/bash
echo "=== Exporting Resample Isotropic Volume Task Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# ============================================================
# Record task end time
# ============================================================
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# ============================================================
# Take final screenshot
# ============================================================
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE=0
if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
fi

# ============================================================
# Check if Slicer is running
# ============================================================
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
else
    echo "WARNING: Slicer is not running"
fi

# ============================================================
# Query Slicer scene for volume information
# ============================================================
echo "Querying Slicer scene for volumes..."

# Create Python script to extract volume information
cat > /tmp/query_volumes.py << 'PYEOF'
#!/usr/bin/env python3
import json
import sys
import os

result = {
    "slicer_running": True,
    "volumes_found": 0,
    "output_volume_found": False,
    "output_volume_name": None,
    "output_spacing": [None, None, None],
    "output_dimensions": [None, None, None],
    "is_isotropic": False,
    "spacing_is_1mm": False,
    "input_volume_found": False,
    "input_spacing": [None, None, None],
    "input_dimensions": [None, None, None],
    "z_dimension_increased": False,
    "all_volumes": [],
    "error": None
}

try:
    import slicer
    
    # Get all scalar volume nodes
    volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    result["volumes_found"] = len(volume_nodes)
    
    for node in volume_nodes:
        name = node.GetName()
        spacing = list(node.GetSpacing())
        
        # Get dimensions
        dims = [0, 0, 0]
        if node.GetImageData():
            dims = list(node.GetImageData().GetDimensions())
        
        vol_info = {
            "name": name,
            "spacing": [float(s) for s in spacing],
            "dimensions": [int(d) for d in dims]
        }
        result["all_volumes"].append(vol_info)
        
        name_lower = name.lower()
        
        # Check if this is the output volume (contains "isotropic")
        if "isotropic" in name_lower:
            result["output_volume_found"] = True
            result["output_volume_name"] = name
            result["output_spacing"] = vol_info["spacing"]
            result["output_dimensions"] = vol_info["dimensions"]
            
            # Check if isotropic (all spacings within 5% of each other)
            sp = vol_info["spacing"]
            if sp[0] > 0 and sp[1] > 0 and sp[2] > 0:
                max_sp = max(sp)
                min_sp = min(sp)
                result["is_isotropic"] = (max_sp - min_sp) / max_sp < 0.05
            
            # Check if spacing is approximately 1.0mm
            result["spacing_is_1mm"] = all(abs(s - 1.0) < 0.15 for s in sp)
        
        # Check if this is the input volume (contains "amos" but not "isotropic")
        elif "amos" in name_lower and "isotropic" not in name_lower:
            result["input_volume_found"] = True
            result["input_spacing"] = vol_info["spacing"]
            result["input_dimensions"] = vol_info["dimensions"]
    
    # Check if z-dimension increased appropriately
    if result["output_volume_found"] and result["input_volume_found"]:
        input_z = result["input_dimensions"][2] if result["input_dimensions"][2] else 0
        output_z = result["output_dimensions"][2] if result["output_dimensions"][2] else 0
        if input_z > 0:
            z_ratio = output_z / input_z
            result["z_dimension_increased"] = z_ratio > 1.5
            result["z_dimension_ratio"] = z_ratio

except Exception as e:
    result["error"] = str(e)
    result["slicer_running"] = False

# Write result to file
output_path = "/tmp/slicer_volume_state.json"
with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

chmod 644 /tmp/query_volumes.py

# Try to run the query script in Slicer
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Executing volume query in Slicer..."
    
    # Method 1: Try using Slicer's Python directly (if accessible)
    timeout 30 sudo -u ga DISPLAY=:1 /opt/Slicer/bin/PythonSlicer /tmp/query_volumes.py 2>/dev/null || {
        echo "Direct Python execution failed, trying alternative method..."
        
        # Method 2: Launch Slicer with --python-script (creates new instance briefly)
        timeout 60 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/query_volumes.py --no-splash --no-main-window 2>/dev/null || {
            echo "WARNING: Could not query Slicer scene programmatically"
        }
    }
    
    sleep 3
fi

# ============================================================
# Read the query results
# ============================================================
VOLUMES_FOUND=0
OUTPUT_VOLUME_FOUND="false"
OUTPUT_VOLUME_NAME=""
OUTPUT_SPACING_X=""
OUTPUT_SPACING_Y=""
OUTPUT_SPACING_Z=""
OUTPUT_DIM_X=""
OUTPUT_DIM_Y=""
OUTPUT_DIM_Z=""
IS_ISOTROPIC="false"
SPACING_IS_1MM="false"
INPUT_DIM_Z=""
Z_DIM_INCREASED="false"

if [ -f /tmp/slicer_volume_state.json ]; then
    echo "Reading volume state from Slicer query..."
    
    VOLUMES_FOUND=$(python3 -c "import json; print(json.load(open('/tmp/slicer_volume_state.json')).get('volumes_found', 0))" 2>/dev/null || echo "0")
    OUTPUT_VOLUME_FOUND=$(python3 -c "import json; print('true' if json.load(open('/tmp/slicer_volume_state.json')).get('output_volume_found', False) else 'false')" 2>/dev/null || echo "false")
    OUTPUT_VOLUME_NAME=$(python3 -c "import json; print(json.load(open('/tmp/slicer_volume_state.json')).get('output_volume_name', '') or '')" 2>/dev/null || echo "")
    
    OUTPUT_SPACING_X=$(python3 -c "import json; sp=json.load(open('/tmp/slicer_volume_state.json')).get('output_spacing', [None,None,None]); print(sp[0] if sp[0] is not None else '')" 2>/dev/null || echo "")
    OUTPUT_SPACING_Y=$(python3 -c "import json; sp=json.load(open('/tmp/slicer_volume_state.json')).get('output_spacing', [None,None,None]); print(sp[1] if sp[1] is not None else '')" 2>/dev/null || echo "")
    OUTPUT_SPACING_Z=$(python3 -c "import json; sp=json.load(open('/tmp/slicer_volume_state.json')).get('output_spacing', [None,None,None]); print(sp[2] if sp[2] is not None else '')" 2>/dev/null || echo "")
    
    OUTPUT_DIM_X=$(python3 -c "import json; d=json.load(open('/tmp/slicer_volume_state.json')).get('output_dimensions', [None,None,None]); print(d[0] if d[0] is not None else '')" 2>/dev/null || echo "")
    OUTPUT_DIM_Y=$(python3 -c "import json; d=json.load(open('/tmp/slicer_volume_state.json')).get('output_dimensions', [None,None,None]); print(d[1] if d[1] is not None else '')" 2>/dev/null || echo "")
    OUTPUT_DIM_Z=$(python3 -c "import json; d=json.load(open('/tmp/slicer_volume_state.json')).get('output_dimensions', [None,None,None]); print(d[2] if d[2] is not None else '')" 2>/dev/null || echo "")
    
    IS_ISOTROPIC=$(python3 -c "import json; print('true' if json.load(open('/tmp/slicer_volume_state.json')).get('is_isotropic', False) else 'false')" 2>/dev/null || echo "false")
    SPACING_IS_1MM=$(python3 -c "import json; print('true' if json.load(open('/tmp/slicer_volume_state.json')).get('spacing_is_1mm', False) else 'false')" 2>/dev/null || echo "false")
    Z_DIM_INCREASED=$(python3 -c "import json; print('true' if json.load(open('/tmp/slicer_volume_state.json')).get('z_dimension_increased', False) else 'false')" 2>/dev/null || echo "false")
    
    INPUT_DIM_Z=$(python3 -c "import json; d=json.load(open('/tmp/slicer_volume_state.json')).get('input_dimensions', [None,None,None]); print(d[2] if d[2] is not None else '')" 2>/dev/null || echo "")
    
    echo "  Volumes found: $VOLUMES_FOUND"
    echo "  Output volume found: $OUTPUT_VOLUME_FOUND"
    echo "  Output volume name: $OUTPUT_VOLUME_NAME"
    echo "  Output spacing: ($OUTPUT_SPACING_X, $OUTPUT_SPACING_Y, $OUTPUT_SPACING_Z)"
    echo "  Output dimensions: ($OUTPUT_DIM_X, $OUTPUT_DIM_Y, $OUTPUT_DIM_Z)"
    echo "  Is isotropic: $IS_ISOTROPIC"
    echo "  Spacing is 1mm: $SPACING_IS_1MM"
    echo "  Z dimension increased: $Z_DIM_INCREASED"
else
    echo "WARNING: Could not read Slicer volume state"
fi

# ============================================================
# Load initial state for comparison
# ============================================================
INITIAL_SPACING_X=""
INITIAL_SPACING_Y=""
INITIAL_SPACING_Z=""
INITIAL_DIM_X=""
INITIAL_DIM_Y=""
INITIAL_DIM_Z=""

if [ -f /tmp/initial_volume_state.json ]; then
    INITIAL_SPACING_X=$(python3 -c "import json; sp=json.load(open('/tmp/initial_volume_state.json')).get('original_spacing_mm', []); print(sp[0] if len(sp)>0 else '')" 2>/dev/null || echo "")
    INITIAL_SPACING_Y=$(python3 -c "import json; sp=json.load(open('/tmp/initial_volume_state.json')).get('original_spacing_mm', []); print(sp[1] if len(sp)>1 else '')" 2>/dev/null || echo "")
    INITIAL_SPACING_Z=$(python3 -c "import json; sp=json.load(open('/tmp/initial_volume_state.json')).get('original_spacing_mm', []); print(sp[2] if len(sp)>2 else '')" 2>/dev/null || echo "")
    INITIAL_DIM_X=$(python3 -c "import json; d=json.load(open('/tmp/initial_volume_state.json')).get('original_dimensions', []); print(d[0] if len(d)>0 else '')" 2>/dev/null || echo "")
    INITIAL_DIM_Y=$(python3 -c "import json; d=json.load(open('/tmp/initial_volume_state.json')).get('original_dimensions', []); print(d[1] if len(d)>1 else '')" 2>/dev/null || echo "")
    INITIAL_DIM_Z=$(python3 -c "import json; d=json.load(open('/tmp/initial_volume_state.json')).get('original_dimensions', []); print(d[2] if len(d)>2 else '')" 2>/dev/null || echo "")
    
    echo ""
    echo "Initial state comparison:"
    echo "  Initial spacing: ($INITIAL_SPACING_X, $INITIAL_SPACING_Y, $INITIAL_SPACING_Z)"
    echo "  Initial dimensions: ($INITIAL_DIM_X, $INITIAL_DIM_Y, $INITIAL_DIM_Z)"
fi

# ============================================================
# Create final result JSON
# ============================================================
echo ""
echo "Creating result JSON..."

RESULT_JSON="/tmp/task_result.json"
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_id": "resample_isotropic_volume@1",
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "slicer_running": $SLICER_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_bytes": $SCREENSHOT_SIZE,
    "volumes_found": $VOLUMES_FOUND,
    "output_volume_found": $OUTPUT_VOLUME_FOUND,
    "output_volume_name": "$OUTPUT_VOLUME_NAME",
    "output_spacing_x": ${OUTPUT_SPACING_X:-null},
    "output_spacing_y": ${OUTPUT_SPACING_Y:-null},
    "output_spacing_z": ${OUTPUT_SPACING_Z:-null},
    "output_dim_x": ${OUTPUT_DIM_X:-null},
    "output_dim_y": ${OUTPUT_DIM_Y:-null},
    "output_dim_z": ${OUTPUT_DIM_Z:-null},
    "is_isotropic": $IS_ISOTROPIC,
    "spacing_is_1mm": $SPACING_IS_1MM,
    "z_dimension_increased": $Z_DIM_INCREASED,
    "initial_spacing_x": ${INITIAL_SPACING_X:-null},
    "initial_spacing_y": ${INITIAL_SPACING_Y:-null},
    "initial_spacing_z": ${INITIAL_SPACING_Z:-null},
    "initial_dim_x": ${INITIAL_DIM_X:-null},
    "initial_dim_y": ${INITIAL_DIM_Y:-null},
    "initial_dim_z": ${INITIAL_DIM_Z:-null},
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f "$RESULT_JSON" 2>/dev/null || sudo rm -f "$RESULT_JSON" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_JSON" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_JSON"
chmod 666 "$RESULT_JSON" 2>/dev/null || sudo chmod 666 "$RESULT_JSON" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Complete ==="
echo "Result saved to: $RESULT_JSON"
cat "$RESULT_JSON"