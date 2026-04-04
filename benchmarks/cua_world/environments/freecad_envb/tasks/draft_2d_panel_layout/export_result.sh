#!/bin/bash
echo "=== Exporting draft_2d_panel_layout results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/FreeCAD/panel_layout.FCStd"

# 1. Check file existence and timestamps
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Python Script to Analyze FreeCAD Geometry (run inside FreeCAD's python env)
# We create a temporary python script and run it with freecadcmd
CAT_SCRIPT="/tmp/analyze_panel.py"
cat > "$CAT_SCRIPT" << 'PYEOF'
import FreeCAD
import json
import sys
import math

result = {
    "objects": [],
    "error": None
}

try:
    # Try to open the document
    try:
        doc = FreeCAD.openDocument("/home/ga/Documents/FreeCAD/panel_layout.FCStd")
    except Exception as e:
        # If file doesn't exist or is invalid
        raise Exception(f"Could not open file: {e}")

    # Iterate through objects
    for obj in doc.Objects:
        obj_data = {
            "name": obj.Name,
            "type": obj.TypeId,
            "label": obj.Label,
            "bbox_size": [0,0,0],
            "center": [0,0,0],
            "is_circle": False,
            "radius": 0,
            "text_content": ""
        }

        # Geometry Analysis
        if hasattr(obj, "Shape") and not obj.Shape.isNull():
            bb = obj.Shape.BoundBox
            obj_data["bbox_size"] = [bb.XLength, bb.YLength, bb.ZLength]
            obj_data["center"] = [bb.Center.x, bb.Center.y, bb.Center.z]
            
            # Check if it looks like a circle (ShapeType can be checked, or properties)
            # Draft Circles usually have a 'Radius' property
            if hasattr(obj, "Radius"):
                obj_data["is_circle"] = True
                obj_data["radius"] = float(obj.Radius)
            elif "Circle" in obj.TypeId:
                obj_data["is_circle"] = True

        # Annotation Analysis (Text/Dimensions)
        # Dimensions usually have "Distance" property or similar
        # Text usually has "Text" property
        if hasattr(obj, "Text"):
            # Can be a list of strings or a string
            txt = obj.Text
            if isinstance(txt, list):
                obj_data["text_content"] = " ".join(txt)
            else:
                obj_data["text_content"] = str(txt)
        
        # Dimensions often store value in a computed property or ViewObject, 
        # but checking the Label or type is often a good proxy for existence.
        if "Dimension" in obj.TypeId:
            obj_data["is_dimension"] = True

        result["objects"].append(obj_data)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Run the analysis
# We use freecadcmd. Note: We need to filter stdout because freecadcmd prints startup info
ANALYSIS_JSON="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    # Run freecadcmd, grep for the JSON line (it will be the last line usually)
    # We pipe stderr to null to avoid noise
    RAW_OUTPUT=$(freecadcmd "$CAT_SCRIPT" 2>/dev/null | grep "^{.*}$" | tail -n 1)
    if [ -n "$RAW_OUTPUT" ]; then
        ANALYSIS_JSON="$RAW_OUTPUT"
    else
        ANALYSIS_JSON='{"error": "Failed to parse FreeCAD output"}'
    fi
else
    ANALYSIS_JSON='{"error": "File not found"}'
fi

# 3. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Construct Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json