#!/bin/bash
echo "=== Exporting create_stepped_shaft result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/FreeCAD/stepped_shaft.FCStd"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file existence and timestamp
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Run geometric analysis using FreeCAD's Python console (headless)
# We embed the python script here
cat > /tmp/analyze_shaft.py << 'PYEOF'
import sys
import json
import math
import FreeCAD
import Part

result = {
    "valid_geometry": False,
    "n_solids": 0,
    "bbox": {"x": 0, "y": 0, "z": 0},
    "volume": 0,
    "sections": {},
    "error": ""
}

try:
    doc = FreeCAD.open("/home/ga/Documents/FreeCAD/stepped_shaft.FCStd")
    
    # Find the main solid
    # We look for the single largest solid in the document
    main_solid = None
    max_vol = 0
    
    for obj in doc.Objects:
        if hasattr(obj, "Shape") and not obj.Shape.isNull():
            if obj.Shape.Solid:
                # Check if it's a compound of solids or a single solid
                solids = obj.Shape.Solids
                current_vol = obj.Shape.Volume
                if current_vol > max_vol:
                    max_vol = current_vol
                    main_solid = obj.Shape

    if main_solid:
        result["valid_geometry"] = True
        result["n_solids"] = len(main_solid.Solids)
        result["volume"] = main_solid.Volume
        
        bb = main_solid.BoundBox
        result["bbox"] = {
            "x": bb.XLength,
            "y": bb.YLength,
            "z": bb.ZLength
        }
        
        # Check cross-sections at specific heights
        # Heights to check: 7.5 (dia 8), 27.5 (dia 12), 50.0 (dia 10)
        check_points = [
            {"z": 7.5, "name": "section_1"},
            {"z": 27.5, "name": "section_2"},
            {"z": 50.0, "name": "section_3"}
        ]
        
        for pt in check_points:
            try:
                # Create a cut plane
                z = pt["z"] + bb.ZMin  # Relative to bottom of object
                # Slice the shape
                # We use a trick: make a large face at Z and find common/section
                # Or simpler: get bounding box of a thin slice
                slice_box = Part.makeBox(100, 100, 0.1, FreeCAD.Vector(-50, -50, z))
                # Intersect
                common = main_solid.common(slice_box)
                if common.Volume > 0:
                    cbb = common.BoundBox
                    # Diameter is roughly max of X/Y length
                    dia = max(cbb.XLength, cbb.YLength)
                    result["sections"][pt["name"]] = dia
                else:
                    result["sections"][pt["name"]] = 0
            except Exception as e:
                result["sections"][pt["name"]] = -1
                
    else:
        result["error"] = "No solid found in document"

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Execute analysis
GEOMETRY_RESULT="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    echo "Running geometry analysis..."
    # We use freecadcmd if available, or python with FreeCAD lib path if needed
    # Usually `freecadcmd` is available in path
    GEOMETRY_RESULT=$(freecadcmd /tmp/analyze_shaft.py 2>/dev/null | grep "^{.*}" | tail -n 1 || echo "{}")
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "FreeCAD" > /dev/null && echo "true" || echo "false")

# Create final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "geometry_analysis": $GEOMETRY_RESULT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="