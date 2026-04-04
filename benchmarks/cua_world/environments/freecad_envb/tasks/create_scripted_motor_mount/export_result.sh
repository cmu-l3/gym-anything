#!/bin/bash
echo "=== Exporting create_scripted_motor_mount results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/FreeCAD/motor_mount_plate.FCStd"
LOG_PATH="/tmp/freecad_task.log"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check file existence and timestamp
if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
fi

# 2. Check if FreeCAD was running
APP_RUNNING=$(pgrep -f "freecad" > /dev/null && echo "true" || echo "false")

# 3. Analyze Geometry (Headless FreeCAD)
# We create a python script to run inside FreeCAD's python environment
ANALYSIS_SCRIPT="/tmp/analyze_geometry.py"
cat > "$ANALYSIS_SCRIPT" << EOF
import FreeCAD
import Part
import json
import sys

try:
    doc = FreeCAD.open("$OUTPUT_PATH")
    result = {
        "valid_solid": False,
        "bbox": [0, 0, 0],
        "volume": 0,
        "faces": 0,
        "cyl_faces": 0,
        "is_valid": False,
        "error": None
    }
    
    # Find the main solid (usually the last active object or the one with a Shape)
    solid_obj = None
    
    # Iterate to find a valid solid
    for obj in doc.Objects:
        if hasattr(obj, "Shape") and obj.Shape.Solids:
            # We assume the user created one final object. 
            # If multiple, we pick the one with the largest volume (likely the finished part).
            if solid_obj is None or obj.Shape.Volume > solid_obj.Shape.Volume:
                solid_obj = obj

    if solid_obj:
        s = solid_obj.Shape
        result["valid_solid"] = True
        result["bbox"] = [s.BoundBox.XLength, s.BoundBox.YLength, s.BoundBox.ZLength]
        result["volume"] = s.Volume
        result["faces"] = len(s.Faces)
        # Count cylindrical faces (holes/curved edges)
        # Face surface string repr usually contains "Cylinder"
        result["cyl_faces"] = sum(1 for f in s.Faces if "Cylinder" in str(f.Surface))
        result["is_valid"] = s.isValid()
    else:
        result["error"] = "No solid found in document"

except Exception as e:
    result = {"error": str(e)}

print("JSON_RESULT:" + json.dumps(result))
EOF

# Run the analysis script using freecadcmd (headless)
GEOMETRY_JSON="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    echo "Running geometry analysis..."
    # freecadcmd might print banners, so we grep for our JSON_RESULT tag
    ANALYSIS_OUTPUT=$(freecadcmd "$ANALYSIS_SCRIPT" 2>&1 || true)
    GEOMETRY_JSON=$(echo "$ANALYSIS_OUTPUT" | grep "JSON_RESULT:" | sed 's/JSON_RESULT://' || echo "{}")
fi

# 4. Check for evidence of scripting (grep logs for keywords)
# We look for common commands expected in the console
SCRIPT_EVIDENCE="false"
if [ -f "$LOG_PATH" ]; then
    if grep -E "Part.makeBox|Part.makeCylinder|Part.makeSphere|App.ActiveDocument.addObject" "$LOG_PATH" > /dev/null; then
        SCRIPT_EVIDENCE="true"
    fi
fi

# 5. Compile Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "geometry": $GEOMETRY_JSON,
    "script_evidence_found": $SCRIPT_EVIDENCE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="