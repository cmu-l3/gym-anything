#!/bin/bash
set -e
echo "=== Exporting create_shaft_keyway results ==="

source /workspace/scripts/task_utils.sh

# Output file path
OUTPUT_FILE="/home/ga/Documents/FreeCAD/drive_shaft_keyway.FCStd"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check file existence and timestamps
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MOD=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MOD" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Analyze Geometry using FreeCAD Python API (inside container)
# We write a temporary python script to extract geometry data
cat > /tmp/analyze_geometry.py << 'PYEOF'
import sys
import json
import math

result = {
    "valid_fcstd": False,
    "has_solid": False,
    "bbox": [0, 0, 0],
    "volume": 0,
    "faces": 0,
    "error": None
}

try:
    # Append FreeCAD lib paths
    sys.path.append('/usr/lib/freecad/lib')
    import FreeCAD
    
    # Open document
    doc = FreeCAD.openDocument('/home/ga/Documents/FreeCAD/drive_shaft_keyway.FCStd')
    result["valid_fcstd"] = True
    
    # Find the final solid shape
    # We look for the last object that has a Shape and Volume > 0
    shape = None
    for obj in reversed(doc.Objects):
        if hasattr(obj, 'Shape') and hasattr(obj.Shape, 'Volume') and obj.Shape.Volume > 0:
            # Check visibility if possible, otherwise assume last object is result
            if obj.ViewObject and obj.ViewObject.Visibility:
                shape = obj.Shape
                break
            if shape is None: # Fallback
                shape = obj.Shape
                
    if shape:
        result["has_solid"] = True
        result["volume"] = shape.Volume
        result["faces"] = len(shape.Faces)
        bb = shape.BoundBox
        # Sort dimensions to handle orientation invariance
        dims = sorted([bb.XLength, bb.YLength, bb.ZLength])
        result["bbox"] = dims
    
    FreeCAD.closeDocument(doc.Name)

except Exception as e:
    result["error"] = str(e)

# Output result to file
with open('/tmp/geometry_analysis.json', 'w') as f:
    json.dump(result, f)
PYEOF

# Run the analysis script
# Try using freecadcmd if available, otherwise python3
if [ "$FILE_EXISTS" = "true" ]; then
    echo "Running geometry analysis..."
    if which freecadcmd > /dev/null 2>&1; then
        freecadcmd /tmp/analyze_geometry.py > /dev/null 2>&1 || true
    else
        # Fallback to python3 with env vars
        export PYTHONPATH=$PYTHONPATH:/usr/lib/freecad/lib
        python3 /tmp/analyze_geometry.py > /dev/null 2>&1 || true
    fi
else
    # Create empty failure result
    echo '{"valid_fcstd": false, "error": "File not found"}' > /tmp/geometry_analysis.json
fi

# Read the analysis result
GEOMETRY_JSON=$(cat /tmp/geometry_analysis.json 2>/dev/null || echo "{}")

# 3. Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "geometry": $GEOMETRY_JSON
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="