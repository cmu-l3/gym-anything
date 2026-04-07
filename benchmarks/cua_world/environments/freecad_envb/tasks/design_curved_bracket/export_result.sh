#!/bin/bash
echo "=== Exporting design_curved_bracket results ==="

source /workspace/scripts/task_utils.sh

# Paths
FCSTD_PATH="/home/ga/Documents/FreeCAD/curved_bracket.FCStd"
STEP_PATH="/home/ga/Documents/FreeCAD/curved_bracket.step"
STEP_PATH2="/home/ga/Documents/FreeCAD/curved_bracket.stp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check file existence and timestamps
FCSTD_EXISTS="false"
STEP_EXISTS="false"
FILES_NEW="false"
FCSTD_SIZE="0"
STEP_SIZE="0"

if [ -f "$FCSTD_PATH" ]; then
    FCSTD_EXISTS="true"
    FCSTD_SIZE=$(stat -c %s "$FCSTD_PATH" 2>/dev/null || echo "0")
    MTIME=$(stat -c %Y "$FCSTD_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILES_NEW="true"
    fi
fi

ACTUAL_STEP_PATH="$STEP_PATH"
if [ -f "$STEP_PATH" ]; then
    STEP_EXISTS="true"
    STEP_SIZE=$(stat -c %s "$STEP_PATH" 2>/dev/null || echo "0")
elif [ -f "$STEP_PATH2" ]; then
    STEP_EXISTS="true"
    ACTUAL_STEP_PATH="$STEP_PATH2"
    STEP_SIZE=$(stat -c %s "$STEP_PATH2" 2>/dev/null || echo "0")
fi

# Run geometric verification inside the container using FreeCAD's Python API
cat > /tmp/analyze_geometry.py << 'PYEOF'
import FreeCAD
import Part
import json
import os

result = {
    "valid_shape": False,
    "shape_type": "None",
    "num_solids": 0,
    "volume": 0.0,
    "bbox": [0.0, 0.0, 0.0],
    "num_faces": 0,
    "cylindrical_faces": [],
    "feature_types": {},
    "error": None
}

fcstd_path = "/home/ga/Documents/FreeCAD/curved_bracket.FCStd"
step_path = "/home/ga/Documents/FreeCAD/curved_bracket.step"
step_path2 = "/home/ga/Documents/FreeCAD/curved_bracket.stp"

shape = None

try:
    # Try loading FCStd first
    if os.path.exists(fcstd_path):
        try:
            doc = FreeCAD.open(fcstd_path)

            # Collect feature types from document
            for obj in doc.Objects:
                tid = obj.TypeId
                result["feature_types"][tid] = result["feature_types"].get(tid, 0) + 1

            # Find the visible solid in the document (largest volume)
            best_vol = 0
            for obj in doc.Objects:
                if hasattr(obj, "Shape") and obj.Shape.Volume > 100:
                    if obj.Shape.Volume > best_vol:
                        best_vol = obj.Shape.Volume
                        shape = obj.Shape
        except Exception as e:
            result["error"] = "FCStd load error: " + str(e)

    # Fallback to STEP if FCStd failed or didn't yield a shape
    actual_step = step_path if os.path.exists(step_path) else (step_path2 if os.path.exists(step_path2) else None)
    if shape is None and actual_step:
        try:
            shape = Part.read(actual_step)
        except Exception as e:
            err_msg = "STEP load error: " + str(e)
            if result["error"]:
                result["error"] += "; " + err_msg
            else:
                result["error"] = err_msg

    # Analyze shape if found
    if shape is not None:
        result["valid_shape"] = shape.isValid()
        result["shape_type"] = shape.ShapeType
        result["volume"] = shape.Volume

        bb = shape.BoundBox
        result["bbox"] = [bb.XLength, bb.YLength, bb.ZLength]
        result["num_faces"] = len(shape.Faces)

        if hasattr(shape, "Solids"):
            result["num_solids"] = len(shape.Solids)
        elif shape.ShapeType == "Solid":
            result["num_solids"] = 1

        # Extract cylindrical face diameters (for detecting bolt holes)
        diameters = []
        for face in shape.Faces:
            surf = face.Surface
            if "Cylinder" in str(type(surf)):
                d = round(surf.Radius * 2, 2)
                diameters.append(d)
        result["cylindrical_faces"] = sorted(set(diameters))

    else:
        if not result["error"]:
            result["error"] = "No geometry found in output files"

except Exception as e:
    result["error"] = "Script crash: " + str(e)

print(json.dumps(result))
PYEOF

# Execute the analysis script using freecadcmd
echo "Running geometric analysis..."
GEOMETRY_JSON="{}"
if [ "$FCSTD_EXISTS" = "true" ] || [ "$STEP_EXISTS" = "true" ]; then
    GEOMETRY_OUTPUT=$(timeout 30s su - ga -c "DISPLAY=:1 freecadcmd /tmp/analyze_geometry.py" 2>&1) || true

    # Extract the JSON part (grep for line starting with '{' — freecadcmd outputs
    # progress bars with carriage returns that corrupt tail-based extraction)
    GEOMETRY_JSON=$(echo "$GEOMETRY_OUTPUT" | grep -E '^\{' | head -n 1)

    # Validate if output is actual JSON
    if ! echo "$GEOMETRY_JSON" | python3 -c "import sys, json; json.load(sys.stdin)" > /dev/null 2>&1; then
        GEOMETRY_JSON="{\"error\": \"Failed to parse analysis output\"}"
    fi
else
    GEOMETRY_JSON="{\"error\": \"No output files found\"}"
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
    "fcstd_size": $FCSTD_SIZE,
    "step_exists": $STEP_EXISTS,
    "step_size": $STEP_SIZE,
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
