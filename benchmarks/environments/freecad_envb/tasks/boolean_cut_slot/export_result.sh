#!/bin/bash
set -e
echo "=== Exporting boolean_cut_slot results ==="
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_FILE="/home/ga/Documents/FreeCAD/slotted_cylinder.FCStd"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check file existence and timestamps
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Analyze the FreeCAD file using a Python script inside the container
# We write the script to a temp file and run it with freecadcmd
ANALYSIS_SCRIPT="/tmp/analyze_cut.py"
cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import sys
import json
import FreeCAD

result = {
    "cut_object_present": False,
    "volume": 0.0,
    "face_count": 0,
    "bbox_x": 0.0,
    "bbox_y": 0.0,
    "bbox_z": 0.0,
    "valid_shape": False,
    "error": None
}

try:
    doc_path = sys.argv[1]
    doc = FreeCAD.open(doc_path)
    
    # Strategy: Find the most likely "result" object.
    # It should be a Cut object, or at least the last solid created.
    target_obj = None
    
    # Look for explicit Cut object
    for obj in doc.Objects:
        type_id = getattr(obj, "TypeId", "")
        if "Cut" in type_id:
            result["cut_object_present"] = True
            target_obj = obj
            # If we find a cut, we prefer it, but keep checking in case there are multiple
            # We'll take the one with the largest volume that isn't infinite
            
    # If no Cut object, check for any solid with substantial volume (fallback)
    if not target_obj:
        for obj in doc.Objects:
            if hasattr(obj, "Shape") and obj.Shape.isValid() and obj.Shape.Volume > 1000:
                target_obj = obj

    if target_obj and hasattr(target_obj, "Shape") and target_obj.Shape.isValid():
        shape = target_obj.Shape
        result["valid_shape"] = True
        result["volume"] = shape.Volume
        result["face_count"] = len(shape.Faces)
        bb = shape.BoundBox
        result["bbox_x"] = bb.XLength
        result["bbox_y"] = bb.YLength
        result["bbox_z"] = bb.ZLength
    
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Run the analysis if file exists
GEOMETRY_DATA="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    # Use freecadcmd to run the python script. 
    # Grep for the JSON output (in case of other stdout noise)
    RAW_OUTPUT=$(freecadcmd "$ANALYSIS_SCRIPT" "$OUTPUT_FILE" 2>/dev/null | grep "^{" | head -n 1 || echo "")
    if [ -n "$RAW_OUTPUT" ]; then
        GEOMETRY_DATA="$RAW_OUTPUT"
    fi
fi

# 4. Create final result JSON
# We combine shell checks and python analysis
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "geometry_analysis": $GEOMETRY_DATA
}
EOF

# Move to standard location with lenient permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="