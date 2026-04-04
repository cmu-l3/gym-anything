#!/bin/bash
set -e
echo "=== Exporting create_loft_transition results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/FreeCAD/loft_transition.FCStd"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check file existence and timestamp
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
fi

# 3. Run internal FreeCAD analysis script
# We run this INSIDE the container to use the FreeCAD Python API
# This avoids needing FreeCAD on the verifier host

ANALYSIS_JSON="/tmp/fc_analysis.json"
echo "{}" > "$ANALYSIS_JSON"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Running FreeCAD geometry analysis..."
    
    cat > /tmp/analyze_loft.py << 'PYEOF'
import FreeCAD
import json
import sys
import os

result = {
    "valid_solid": False,
    "volume": 0.0,
    "bbox": [0, 0, 0, 0, 0, 0],
    "has_loft": False,
    "sketch_count": 0,
    "features": []
}

try:
    doc_path = "/home/ga/Documents/FreeCAD/loft_transition.FCStd"
    if not os.path.exists(doc_path):
        raise Exception("File not found")
        
    doc = FreeCAD.open(doc_path)
    
    # Analyze objects
    for obj in doc.Objects:
        result["features"].append(obj.TypeId)
        
        # Check for Loft
        if "Loft" in obj.TypeId or "AdditiveLoft" in obj.TypeId:
            result["has_loft"] = True
            
        # Count sketches
        if "Sketch" in obj.TypeId:
            result["sketch_count"] += 1
            
        # geometric analysis of the final shape
        # We look for the Tip of the active body or the object itself
        if hasattr(obj, "Shape") and obj.Shape.IsValid:
             # We assume the largest solid is the result
             if obj.Shape.Volume > result["volume"]:
                 result["volume"] = obj.Shape.Volume
                 bb = obj.Shape.BoundBox
                 result["bbox"] = [bb.XMin, bb.YMin, bb.ZMin, bb.XMax, bb.YMax, bb.ZMax]
                 if obj.Shape.ShapeType == "Solid":
                     result["valid_solid"] = True

except Exception as e:
    result["error"] = str(e)

with open("/tmp/fc_analysis.json", "w") as f:
    json.dump(result, f)
PYEOF

    # Run headless FreeCAD with the script
    # freecadcmd is the command line version
    timeout 20s freecadcmd /tmp/analyze_loft.py > /dev/null 2>&1 || true
fi

# 4. Merge results into final JSON
# We read the analysis json content
ANALYSIS_CONTENT=$(cat "$ANALYSIS_JSON" 2>/dev/null || echo "{}")

# Create the final result JSON safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "geometry_analysis": $ANALYSIS_CONTENT
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="