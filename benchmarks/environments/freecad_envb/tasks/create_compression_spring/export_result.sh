#!/bin/bash
echo "=== Exporting create_compression_spring results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/FreeCAD/compression_spring.FCStd"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check File Metadata
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MODIFIED_IN_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_IN_TASK="true"
    fi
fi

# 3. Analyze Geometry using FreeCAD Python API (Inside Container)
# We run a python script to extract volume and bounding box
GEOMETRY_JSON="{}"
if [ "$FILE_EXISTS" = "true" ] && [ "$FILE_SIZE" -gt 1000 ]; then
    echo "Analyzing geometry..."
    cat > /tmp/analyze_spring.py << 'PYEOF'
import FreeCAD
import sys
import json
import os

file_path = "/home/ga/Documents/FreeCAD/compression_spring.FCStd"
result = {
    "has_solid": False,
    "volume": 0.0,
    "bbox": [0, 0, 0],
    "solids_count": 0,
    "error": None
}

try:
    if not os.path.exists(file_path):
        result["error"] = "File not found"
    else:
        doc = FreeCAD.open(file_path)
        
        # Find the best candidate solid (largest volume)
        best_vol = 0
        best_shape = None
        
        for obj in doc.Objects:
            if hasattr(obj, 'Shape') and obj.Shape is not None:
                # Check if it has volume (solids)
                if obj.Shape.Volume > 1.0: 
                    result["solids_count"] += 1
                    if obj.Shape.Volume > best_vol:
                        best_vol = obj.Shape.Volume
                        best_shape = obj.Shape
        
        if best_shape:
            result["has_solid"] = True
            result["volume"] = best_vol
            bb = best_shape.BoundBox
            result["bbox"] = [bb.XLength, bb.YLength, bb.ZLength]
            
except Exception as e:
    result["error"] = str(e)

print("JSON_RESULT:" + json.dumps(result))
PYEOF

    # Run the script using system python (which has freecad libs in this env)
    # or freecadcmd if available. Usually python3 works if paths are set, 
    # but freecadcmd is safer for the environment.
    ANALYSIS_OUTPUT=$(freecadcmd /tmp/analyze_spring.py 2>&1 || python3 /tmp/analyze_spring.py 2>&1)
    
    # Extract JSON from output
    GEOMETRY_JSON=$(echo "$ANALYSIS_OUTPUT" | grep "JSON_RESULT:" | sed 's/JSON_RESULT://' || echo "{}")
fi

# 4. Construct Final JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified_in_task": $FILE_MODIFIED_IN_TASK,
    "geometry": $GEOMETRY_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to shared location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="