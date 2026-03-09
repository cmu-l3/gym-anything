#!/bin/bash
echo "=== Exporting create_display_pedestal results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/FreeCAD/display_pedestal.FCStd"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if output file exists
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    # Check if created during task
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

# Analyze geometry using FreeCAD's Python API (headless)
# We run this inside the container to access the FreeCAD libraries
cat > /tmp/analyze_pedestal.py << PYEOF
import FreeCAD
import json
import sys
import math

result = {
    "valid_doc": False,
    "shape_count": 0,
    "is_single_solid": False,
    "volume": 0.0,
    "bbox": [0.0, 0.0, 0.0],
    "face_count": 0,
    "has_hole_topology": False,
    "error": ""
}

try:
    doc_path = "$OUTPUT_PATH"
    try:
        doc = FreeCAD.openDocument(doc_path)
    except Exception as e:
        result["error"] = f"Failed to open document: {str(e)}"
        print(json.dumps(result))
        sys.exit(0)

    result["valid_doc"] = True
    
    # Find the visible/final shape
    # We look for the shape with the largest volume, assuming that's the final part
    max_vol = 0
    final_obj = None
    
    shape_count = 0
    
    for obj in doc.Objects:
        if hasattr(obj, "Shape") and obj.Shape.isValid():
            shape_count += 1
            if obj.Shape.Volume > max_vol:
                max_vol = obj.Shape.Volume
                final_obj = obj
                
    result["shape_count"] = shape_count
    
    if final_obj:
        shape = final_obj.Shape
        result["volume"] = shape.Volume
        
        # Bounding box
        bb = shape.BoundBox
        result["bbox"] = [bb.XLength, bb.YLength, bb.ZLength]
        
        # Check if single solid
        result["is_single_solid"] = (len(shape.Solids) == 1)
        
        # Face count (proxy for complexity/features)
        result["face_count"] = len(shape.Faces)
        
        # Check for hole topology
        # A solid cylinder has 3 faces. A box has 6.
        # A fused pedestal without hole has ~8-12 faces.
        # A hole adds faces.
        # We also check if the bounding box Z is correct but volume is LESS than bbox volume
        # (indicating subtraction).
        
        # More robust hole check: Check for a cylindrical face with negative curvature?
        # Or simply rely on volume + dimensions.
        pass

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Run the analysis script
if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Analyzing geometry..."
    ANALYSIS_JSON=$(freecadcmd /tmp/analyze_pedestal.py 2>/dev/null | grep -v "FreeCAD")
    # Sanitize output to ensure we just get the JSON
    ANALYSIS_JSON=$(echo "$ANALYSIS_JSON" | grep "^{" | tail -n 1)
    
    if [ -z "$ANALYSIS_JSON" ]; then
        ANALYSIS_JSON='{"error": "Failed to parse analysis output"}'
    fi
else
    ANALYSIS_JSON='{"error": "File not found"}'
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "freecad" > /dev/null && echo "true" || echo "false")

# Compile final result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "analysis": $ANALYSIS_JSON
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="