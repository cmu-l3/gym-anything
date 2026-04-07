#!/bin/bash
echo "=== Exporting boolean_intersection_fluid_core result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_PATH="/home/ga/Documents/SolveSpace/fluid_core.slvs"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
INTERSECTION_MODE_USED="false"
STL_VOLUME="0.0"
BOUNDS_X="0.0"
BOUNDS_Y="0.0"
BOUNDS_Z="0.0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check if meshCombine=2 (Intersection) is explicitly used in the SLVS file
    if grep -q "meshCombine=2" "$OUTPUT_PATH"; then
        INTERSECTION_MODE_USED="true"
    fi

    # Export STL using solvespace-cli
    DISPLAY=:1 solvespace-cli export-mesh --stl /tmp/fluid_core.stl "$OUTPUT_PATH" 2>/dev/null || true
    
    if [ -f /tmp/fluid_core.stl ]; then
        # Calculate volume and bounding box using python and trimesh
        PYTHON_OUT=$(python3 << 'EOF'
import json
import sys
try:
    import trimesh
    import numpy as np
    mesh = trimesh.load('/tmp/fluid_core.stl', force='mesh')
    bounds = mesh.extents
    volume = mesh.volume
    print(json.dumps({
        "success": True,
        "bounds": bounds.tolist() if hasattr(bounds, 'tolist') else list(bounds),
        "volume": float(volume)
    }))
except Exception as e:
    print(json.dumps({"success": False, "error": str(e)}))
EOF
        )
        
        STL_SUCCESS=$(echo "$PYTHON_OUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('success', False))" 2>/dev/null || echo "False")
        
        if [ "$STL_SUCCESS" = "True" ]; then
            STL_VOLUME=$(echo "$PYTHON_OUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('volume', 0.0))")
            BOUNDS_X=$(echo "$PYTHON_OUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('bounds', [0,0,0])[0])")
            BOUNDS_Y=$(echo "$PYTHON_OUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('bounds', [0,0,0])[1])")
            BOUNDS_Z=$(echo "$PYTHON_OUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('bounds', [0,0,0])[2])")
        fi
    fi
fi

APP_RUNNING=$(pgrep -f "solvespace" > /dev/null && echo "true" || echo "false")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "intersection_mode_used": $INTERSECTION_MODE_USED,
    "stl_volume": $STL_VOLUME,
    "bounds_x": $BOUNDS_X,
    "bounds_y": $BOUNDS_Y,
    "bounds_z": $BOUNDS_Z,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete:"
cat /tmp/task_result.json