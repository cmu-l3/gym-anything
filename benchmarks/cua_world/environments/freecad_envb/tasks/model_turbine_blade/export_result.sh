#!/bin/bash
echo "=== Exporting model_turbine_blade results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/FreeCAD/turbine_blade.FCStd"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
IS_VALID_DOC="false"
HAS_SOLID="false"
SOLID_HEIGHT="0"
SOLID_VOLUME="0"
BBOX_X_WIDTH="0"
BBOX_Y_WIDTH="0"
ERROR_MSG=""

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # INSPECT GEOMETRY USING FREECAD PYTHON API (HEADLESS)
    # We create a python script to run inside FreeCAD's environment
    cat > /tmp/inspect_blade.py << PYEOF
import FreeCAD
import sys
import json

result = {
    "is_valid": False,
    "has_solid": False,
    "height": 0.0,
    "volume": 0.0,
    "bbox_x": 0.0,
    "bbox_y": 0.0,
    "error": ""
}

try:
    # Open the document
    doc = FreeCAD.openDocument("$OUTPUT_PATH")
    result["is_valid"] = True
    
    # Find solid objects
    solids = []
    for obj in doc.Objects:
        if hasattr(obj, "Shape") and obj.Shape.Solid:
            solids.append(obj.Shape)
            
    if solids:
        result["has_solid"] = True
        # Analyze the largest solid (assuming it's the blade)
        main_solid = max(solids, key=lambda s: s.Volume)
        
        bbox = main_solid.BoundBox
        result["height"] = bbox.ZLength
        result["volume"] = main_solid.Volume
        result["bbox_x"] = bbox.XLength
        result["bbox_y"] = bbox.YLength
        
    else:
        result["error"] = "No solid objects found in document"

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

    # Run inspection
    # Use 'freecadcmd' if available, otherwise 'freecad' in console mode
    INSPECTION_JSON=""
    if which freecadcmd > /dev/null 2>&1; then
        INSPECTION_JSON=$(su - ga -c "freecadcmd /tmp/inspect_blade.py" 2>/dev/null | grep "^{")
    else
        INSPECTION_JSON=$(su - ga -c "freecad -c /tmp/inspect_blade.py" 2>/dev/null | grep "^{")
    fi

    # Parse inspection results
    if [ -n "$INSPECTION_JSON" ]; then
        IS_VALID_DOC=$(echo "$INSPECTION_JSON" | python3 -c "import sys, json; print(str(json.load(sys.stdin).get('is_valid', False)).lower())")
        HAS_SOLID=$(echo "$INSPECTION_JSON" | python3 -c "import sys, json; print(str(json.load(sys.stdin).get('has_solid', False)).lower())")
        SOLID_HEIGHT=$(echo "$INSPECTION_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('height', 0))")
        SOLID_VOLUME=$(echo "$INSPECTION_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('volume', 0))")
        BBOX_X_WIDTH=$(echo "$INSPECTION_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('bbox_x', 0))")
        BBOX_Y_WIDTH=$(echo "$INSPECTION_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('bbox_y', 0))")
        ERROR_MSG=$(echo "$INSPECTION_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('error', ''))")
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "is_valid_doc": $IS_VALID_DOC,
    "has_solid": $HAS_SOLID,
    "solid_height": $SOLID_HEIGHT,
    "solid_volume": $SOLID_VOLUME,
    "bbox_x_width": $BBOX_X_WIDTH,
    "bbox_y_width": $BBOX_Y_WIDTH,
    "error_msg": "$ERROR_MSG",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="