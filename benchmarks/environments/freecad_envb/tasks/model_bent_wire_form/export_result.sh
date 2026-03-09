#!/bin/bash
echo "=== Exporting model_bent_wire_form results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/FreeCAD/seat_frame_wire.FCStd"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check file existence and timestamp
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 3. Run internal geometry analysis using FreeCAD's Python API
# We create a temporary python script to run inside FreeCAD context
cat > /tmp/analyze_geometry.py << 'PYEOF'
import FreeCAD
import Part
import json
import sys
import os

output_path = "/home/ga/Documents/FreeCAD/seat_frame_wire.FCStd"
result = {
    "valid_solid": False,
    "volume": 0.0,
    "bbox": [0, 0, 0],
    "center_of_mass": [0, 0, 0],
    "error": None
}

try:
    if not os.path.exists(output_path):
        result["error"] = "File not found"
    else:
        doc = FreeCAD.openDocument(output_path)
        
        # Find the main solid object
        # We look for the object with the largest volume
        best_obj = None
        max_vol = 0
        
        for obj in doc.Objects:
            if hasattr(obj, 'Shape') and obj.Shape is not None:
                try:
                    if obj.Shape.Solid:
                        vol = obj.Shape.Volume
                        if vol > max_vol:
                            max_vol = vol
                            best_obj = obj
                except Exception:
                    continue
        
        if best_obj:
            shape = best_obj.Shape
            bbox = shape.BoundBox
            
            result["valid_solid"] = True
            result["volume"] = shape.Volume
            result["bbox"] = [bbox.XLength, bbox.YLength, bbox.ZLength]
            result["center_of_mass"] = [shape.CenterOfMass.x, shape.CenterOfMass.y, shape.CenterOfMass.z]
        else:
            result["error"] = "No solid object found in document"

except Exception as e:
    result["error"] = str(e)

with open("/tmp/geometry_analysis.json", "w") as f:
    json.dump(result, f)

PYEOF

# Run the analysis script headlessly
if [ "$FILE_EXISTS" = "true" ]; then
    echo "Running geometry analysis..."
    # We use freecadcmd to run the script without GUI
    su - ga -c "freecadcmd /tmp/analyze_geometry.py" > /dev/null 2>&1 || echo "Analysis failed"
else
    # Create empty failure result
    echo '{"error": "File missing"}' > /tmp/geometry_analysis.json
fi

# 4. Read analysis result
ANALYSIS_CONTENT=$(cat /tmp/geometry_analysis.json 2>/dev/null || echo '{"error": "Analysis not run"}')

# 5. Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "geometry": $ANALYSIS_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="