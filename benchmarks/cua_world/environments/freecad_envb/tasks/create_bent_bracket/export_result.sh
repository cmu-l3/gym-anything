#!/bin/bash
echo "=== Exporting create_bent_bracket results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/FreeCAD/finished_bracket.FCStd"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file existence and timestamp
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

# ==============================================================================
# Analyze the result file using FreeCAD's Python API (Headless)
# We run this INSIDE the container to extract geometric metrics
# ==============================================================================
cat > /tmp/analyze_bracket.py << 'PYEOF'
import FreeCAD
import Part
import sys
import json
import os

result = {
    "valid_file": False,
    "is_solid": False,
    "volume": 0.0,
    "bbox_z": 0.0,
    "faces_count": 0,
    "has_offset": False,
    "has_fillet": False,
    "history": []
}

file_path = "/home/ga/Documents/FreeCAD/finished_bracket.FCStd"

try:
    if os.path.exists(file_path):
        doc = FreeCAD.open(file_path)
        result["valid_file"] = True
        
        # Find the last active object (likely the result)
        # We look for the object with no dependents or simply the last one created
        if doc.Objects:
            # Simple heuristic: assume the last object in list is the final one
            # or look for specific types
            final_obj = doc.Objects[-1]
            
            # Check dependency history
            for obj in doc.Objects:
                result["history"].append(obj.TypeId)
                if "Offset" in obj.TypeId:
                    result["has_offset"] = True
                if "Fillet" in obj.TypeId:
                    result["has_fillet"] = True

            # Analyze geometry of final object
            if hasattr(final_obj, 'Shape') and final_obj.Shape.isValid():
                shape = final_obj.Shape
                result["is_solid"] = shape.ShapeType == 'Solid'
                result["volume"] = shape.Volume
                result["faces_count"] = len(shape.Faces)
                
                bbox = shape.BoundBox
                result["bbox_z"] = bbox.ZLength
                
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Run analysis
ANALYSIS_JSON="{}"
if [ "$FILE_EXISTS" == "true" ]; then
    echo "Running geometry analysis..."
    ANALYSIS_JSON=$(su - ga -c "freecadcmd /tmp/analyze_bracket.py" 2>/dev/null | grep -v "FreeCAD")
    # Fallback if grep failed to isolate JSON
    if [ -z "$ANALYSIS_JSON" ]; then ANALYSIS_JSON="{}"; fi
fi

# Construct final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "geometry_analysis": $ANALYSIS_JSON
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="