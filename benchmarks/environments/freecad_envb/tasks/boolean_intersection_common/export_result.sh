#!/bin/bash
set -e
echo "=== Exporting boolean_intersection_common result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/FreeCAD/workspace_intersection.FCStd"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check File Existence & Timestamp
if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH")
    
    # Check if created during task
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

# 2. Analyze FCStd file content using FreeCAD python interface
# We run this inside the container to avoid needing FreeCAD on the host
ANALYSIS_SCRIPT="/tmp/analyze_intersection.py"
cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import sys
import json
import os

result = {
    "valid_doc": False,
    "object_count": 0,
    "common_found": False,
    "box_count": 0,
    "final_volume": 0.0,
    "error": ""
}

try:
    # Append FreeCAD path if standard path fails
    sys.path.append('/usr/lib/freecad/lib')
    import FreeCAD

    path = "/home/ga/Documents/FreeCAD/workspace_intersection.FCStd"
    
    if os.path.exists(path):
        try:
            doc = FreeCAD.openDocument(path)
            result["valid_doc"] = True
            result["object_count"] = len(doc.Objects)
            
            # Check objects
            for obj in doc.Objects:
                # Check for Boxes
                if hasattr(obj, "TypeId") and "Box" in obj.TypeId:
                    result["box_count"] += 1
                
                # Check for Common/Intersection
                # Note: TypeId might be Part::Common or Part::MultiCommon
                if hasattr(obj, "TypeId") and "Common" in obj.TypeId:
                    result["common_found"] = True
                    if hasattr(obj, "Shape"):
                        result["final_volume"] = obj.Shape.Volume
                
                # Fallback: if user didn't use boolean tool but shape looks right
                elif hasattr(obj, "Shape") and hasattr(obj.Shape, "Volume"):
                     # Check if this object is roughly the expected volume (80000)
                     if 75000 < obj.Shape.Volume < 85000:
                         # Keep track of likely candidate volume if common not found
                         if result["final_volume"] == 0:
                             result["final_volume"] = obj.Shape.Volume

        except Exception as e:
            result["error"] = f"FreeCAD Exception: {str(e)}"
    else:
        result["error"] = "File not found"

except Exception as e:
    result["error"] = f"Script Exception: {str(e)}"

print(json.dumps(result))
PYEOF

# Run analysis if file exists
if [ "$FILE_EXISTS" = "true" ]; then
    echo "Running FreeCAD analysis..."
    # Run with timeout to prevent hangs
    ANALYSIS_OUTPUT=$(timeout 30s freecadcmd "$ANALYSIS_SCRIPT" 2>/dev/null || echo '{"error": "Analysis timeout"}')
    
    # Extract JSON part (freecadcmd might output other text)
    # We look for the last line which should be the JSON
    JSON_OUTPUT=$(echo "$ANALYSIS_OUTPUT" | tail -n 1)
else
    JSON_OUTPUT='{"valid_doc": false, "error": "File missing"}'
fi

# 3. Create final result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "analysis": $JSON_OUTPUT
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json
chmod 666 /tmp/task_final.png

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="