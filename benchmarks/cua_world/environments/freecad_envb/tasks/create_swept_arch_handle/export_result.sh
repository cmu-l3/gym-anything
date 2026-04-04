#!/bin/bash
set -e
echo "=== Exporting create_swept_arch_handle results ==="

source /workspace/scripts/task_utils.sh

# Paths
FCSTD_PATH="/home/ga/Documents/FreeCAD/display_handle.FCStd"
STEP_PATH="/home/ga/Documents/FreeCAD/display_handle.step"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check file existence and timestamps
FCSTD_EXISTS="false"
STEP_EXISTS="false"
FILES_NEW="false"

if [ -f "$FCSTD_PATH" ]; then
    FCSTD_EXISTS="true"
    MTIME=$(stat -c %Y "$FCSTD_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILES_NEW="true"
    fi
fi

if [ -f "$STEP_PATH" ]; then
    STEP_EXISTS="true"
    # If STEP exists but FCStd doesn't, check STEP timestamp
    MTIME=$(stat -c %Y "$STEP_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILES_NEW="true"
    fi
fi

# Run geometric verification inside the container using FreeCAD's Python API
# We create a temporary python script to analyze the geometry
cat > /tmp/analyze_geometry.py << 'PYEOF'
import FreeCAD
import Part
import json
import os
import sys

result = {
    "valid_shape": False,
    "shape_type": "None",
    "num_solids": 0,
    "volume": 0.0,
    "bbox": [0.0, 0.0, 0.0],
    "error": None
}

fcstd_path = "/home/ga/Documents/FreeCAD/display_handle.FCStd"
step_path = "/home/ga/Documents/FreeCAD/display_handle.step"

shape = None

try:
    # Try loading FCStd first
    if os.path.exists(fcstd_path):
        try:
            doc = FreeCAD.open(fcstd_path)
            # Find the visible solid in the document
            for obj in doc.Objects:
                if hasattr(obj, "Shape") and obj.Shape.Volume > 100: # Filter out tiny artifacts
                    shape = obj.Shape
                    # If we found a solid, stick with it
                    if shape.ShapeType == 'Solid' or shape.ShapeType == 'CompSolid':
                        break
        except Exception as e:
            result["error"] = f"FCStd load error: {str(e)}"

    # Fallback to STEP if FCStd failed or didn't yield a shape
    if shape is None and os.path.exists(step_path):
        try:
            shape = Part.read(step_path)
        except Exception as e:
            if result["error"]:
                result["error"] += f"; STEP load error: {str(e)}"
            else:
                result["error"] = f"STEP load error: {str(e)}"

    # Analyze shape if found
    if shape is not None:
        result["valid_shape"] = shape.isValid()
        result["shape_type"] = shape.ShapeType
        result["volume"] = shape.Volume
        
        bb = shape.BoundBox
        result["bbox"] = [bb.XLength, bb.YLength, bb.ZLength]
        
        if hasattr(shape, "Solids"):
            result["num_solids"] = len(shape.Solids)
        elif shape.ShapeType == "Solid":
            result["num_solids"] = 1
        
    else:
        if not result["error"]:
            result["error"] = "No geometry found in output files"

except Exception as e:
    result["error"] = f"Script crash: {str(e)}"

# Print JSON to stdout
print(json.dumps(result))
PYEOF

# Execute the analysis script using freecadcmd
echo "Running geometric analysis..."
GEOMETRY_JSON="{}"
if [ "$FCSTD_EXISTS" = "true" ] || [ "$STEP_EXISTS" = "true" ]; then
    # Use 'timeout' to prevent hanging if FreeCAD loops
    GEOMETRY_OUTPUT=$(timeout 30s su - ga -c "DISPLAY=:1 freecadcmd /tmp/analyze_geometry.py" 2>&1) || true
    
    # Extract the JSON part (last line usually)
    GEOMETRY_JSON=$(echo "$GEOMETRY_OUTPUT" | tail -n 1)
    
    # Validate if output is actual JSON
    if ! echo "$GEOMETRY_JSON" | python3 -c "import sys, json; json.load(sys.stdin)" > /dev/null 2>&1; then
        GEOMETRY_JSON="{\"error\": \"Failed to parse analysis output\", \"raw_output\": \"$(echo $GEOMETRY_OUTPUT | tr -d '"')\"}"
    fi
else
    GEOMETRY_JSON="{\"error\": \"Files not found\"}"
fi

# App Running Check
APP_RUNNING="false"
if pgrep -f "freecad" > /dev/null; then
    APP_RUNNING="true"
fi

# Combine all results into final JSON
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "fcstd_exists": $FCSTD_EXISTS,
    "step_exists": $STEP_EXISTS,
    "files_created_during_task": $FILES_NEW,
    "app_running": $APP_RUNNING,
    "geometry": $GEOMETRY_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="