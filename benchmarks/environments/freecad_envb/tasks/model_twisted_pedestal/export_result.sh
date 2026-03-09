#!/bin/bash
echo "=== Exporting model_twisted_pedestal results ==="

source /workspace/scripts/task_utils.sh

# Task variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/FreeCAD/twisted_pedestal.FCStd"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check file existence and timestamps
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if App is running
APP_RUNNING="false"
if pgrep -f "FreeCAD" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Geometric Analysis via FreeCAD Python API (Headless)
# We run this INSIDE the container to leverage the installed FreeCAD
cat > /tmp/analyze_geometry.py << PYEOF
import FreeCAD
import sys
import json

result = {
    "valid_doc": False,
    "solid_count": 0,
    "has_loft": False,
    "bbox": [0, 0, 0],
    "volume": 0,
    "error": ""
}

try:
    # Open document
    doc = FreeCAD.open("$OUTPUT_FILE")
    result["valid_doc"] = True
    
    solids = []
    
    # Iterate objects
    for obj in doc.Objects:
        # Check for Loft feature type
        if "Loft" in obj.TypeId or (hasattr(obj, "Proxy") and "Loft" in str(obj.Proxy)):
             result["has_loft"] = True
             
        # Check shape
        if hasattr(obj, "Shape") and not obj.Shape.isNull():
            if obj.Shape.Solid:
                solids.append(obj.Shape)
    
    result["solid_count"] = len(solids)
    
    if solids:
        # Analyze the largest solid (in case of construction geometry)
        main_solid = max(solids, key=lambda s: s.Volume)
        bbox = main_solid.BoundBox
        
        result["volume"] = main_solid.Volume
        result["bbox"] = [bbox.XLength, bbox.YLength, bbox.ZLength]
        
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

GEOMETRY_METRICS="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    echo "Running geometry analysis..."
    GEOMETRY_METRICS=$(freecadcmd /tmp/analyze_geometry.py 2>/dev/null | tail -1)
    # Validate if output is JSON, else fallback
    if ! echo "$GEOMETRY_METRICS" | grep -q "valid_doc"; then
        GEOMETRY_METRICS="{\"error\": \"Failed to parse script output\"}"
    fi
else
    GEOMETRY_METRICS="{\"error\": \"File not found\"}"
fi

# 5. Compile Final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "geometry": $GEOMETRY_METRICS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to public location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Results saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="