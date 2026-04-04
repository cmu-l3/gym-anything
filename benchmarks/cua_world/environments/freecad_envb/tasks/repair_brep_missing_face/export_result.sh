#!/bin/bash
echo "=== Exporting Repair Task Results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Target file
OUTPUT_PATH="/home/ga/Documents/FreeCAD/repaired_bracket.FCStd"

# Check file existence and timestamps
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
    OUTPUT_MTIME="0"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# -----------------------------------------------------------------------------
# GEOMETRIC ANALYSIS
# We run a headless FreeCAD script to analyze the agent's file.
# This extracts Volume, ShapeType, Closed status, and CenterOfMass.
# -----------------------------------------------------------------------------
cat > /tmp/analyze_repair.py << 'PYEOF'
import FreeCAD
import Part
import json
import sys
import os

result = {
    "valid_file": False,
    "has_shape": False,
    "shape_type": "None",
    "is_closed": False,
    "volume": 0.0,
    "com_x": 0.0,
    "com_y": 0.0,
    "com_z": 0.0,
    "error": ""
}

file_path = "/home/ga/Documents/FreeCAD/repaired_bracket.FCStd"

if os.path.exists(file_path):
    try:
        doc = FreeCAD.openDocument(file_path)
        result["valid_file"] = True
        
        # Find the best candidate object (Solid with largest volume)
        best_obj = None
        max_vol = -1.0
        
        for obj in doc.Objects:
            if hasattr(obj, 'Shape') and obj.Shape is not None:
                # Check if it has volume (Solid) or just Area (Shell)
                vol = 0
                try:
                    vol = obj.Shape.Volume
                except:
                    vol = 0
                
                # We prioritize Solids, but will inspect Shells if no solid found
                if obj.Shape.ShapeType == 'Solid' and vol > max_vol:
                    max_vol = vol
                    best_obj = obj
                elif best_obj is None and obj.Shape.ShapeType == 'Shell':
                    # Fallback to shell if no solid found yet
                    best_obj = obj
        
        if best_obj:
            shape = best_obj.Shape
            result["has_shape"] = True
            result["shape_type"] = shape.ShapeType
            result["is_closed"] = shape.isClosed()
            result["volume"] = shape.Volume
            result["com_x"] = shape.CenterOfMass.x
            result["com_y"] = shape.CenterOfMass.y
            result["com_z"] = shape.CenterOfMass.z
        else:
            result["error"] = "No geometric objects found in document"
            
    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "File not found"

with open("/tmp/geometry_analysis.json", "w") as f:
    json.dump(result, f)
PYEOF

# Run analysis
if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Running geometric analysis..."
    su - ga -c "freecadcmd /tmp/analyze_repair.py"
else
    # Create empty failure result
    echo '{"valid_file": false, "error": "File missing"}' > /tmp/geometry_analysis.json
fi

# -----------------------------------------------------------------------------
# CREATE FINAL RESULT JSON
# -----------------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Read geometry analysis
GEO_JSON=$(cat /tmp/geometry_analysis.json 2>/dev/null || echo "{}")

# Combine everything
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "geometry_analysis": $GEO_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="