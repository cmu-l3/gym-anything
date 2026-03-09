#!/bin/bash
set -e
echo "=== Exporting create_mounting_holes_plate results ==="

source /workspace/scripts/task_utils.sh

# 1. Define paths
OUTPUT_PATH="/home/ga/Documents/FreeCAD/mounting_plate.FCStd"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 2. Take final screenshot
take_screenshot /tmp/task_final.png

# 3. Check file existence and timestamps
FILE_EXISTS=false
FILE_CREATED_DURING_TASK=false
FILE_SIZE=0

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS=true
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK=true
    fi
fi

# 4. Run internal geometry analysis using FreeCAD Python API
# We create a python script and run it inside the container's FreeCAD environment
# This allows us to inspect the actual geometry (volume, holes, dims) programmatically.

ANALYSIS_SCRIPT="/tmp/analyze_plate.py"
ANALYSIS_OUTPUT="/tmp/geometry_analysis.json"

cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import FreeCAD
import Part
import json
import sys
import math

output = {
    "valid_file": False,
    "solid_found": False,
    "bbox_dims": [0, 0, 0],
    "volume": 0,
    "hole_count": 0,
    "hole_radii": [],
    "hole_centers": [],
    "error": None
}

file_path = "/home/ga/Documents/FreeCAD/mounting_plate.FCStd"

try:
    # Attempt to open document
    doc = FreeCAD.openDocument(file_path)
    output["valid_file"] = True
    
    # Find the main solid (Body or Shape)
    # Strategy: Look for PartDesign::Body first, then any solid object
    target_shape = None
    
    # 1. Check for PartDesign Body
    for obj in doc.Objects:
        if obj.TypeId == 'PartDesign::Body':
            if hasattr(obj, 'Shape') and not obj.Shape.isNull() and obj.Shape.Solid:
                target_shape = obj.Shape
                break
    
    # 2. Fallback to any significant solid
    if not target_shape:
        for obj in doc.Objects:
            if hasattr(obj, 'Shape') and not obj.Shape.isNull() and obj.Shape.Solid:
                # Filter out tiny artifacts
                if obj.Shape.Volume > 1000: 
                    target_shape = obj.Shape
                    break
    
    if target_shape:
        output["solid_found"] = True
        output["volume"] = target_shape.Volume
        
        # Bounding Box
        bb = target_shape.BoundBox
        output["bbox_dims"] = [bb.XLength, bb.YLength, bb.ZLength]
        
        # Analyze Faces for Holes
        # We look for cylindrical faces with radius approx 2.75mm (5.5mm dia)
        # Note: A through hole consists of 1 or 2 semi-cylindrical faces depending on implementation
        # We'll collect all cylindrical faces
        
        for face in target_shape.Faces:
            surf = face.Surface
            # Check if surface is cylindrical (string check avoids import issues)
            if "Cylinder" in str(type(surf)):
                r = surf.Radius
                output["hole_radii"].append(r)
                
                # Get center of the cylinder axis
                # For a plate in XY, the hole axis is parallel to Z
                # The Center property of the surface gives a point on the axis
                c = surf.Center
                output["hole_centers"].append([c.x, c.y, c.z])
                
        # Heuristic for hole count: usually 1 cylinder face per hole if simple, 
        # sometimes split. We'll count distinct axes in the verifier.
        output["hole_count"] = len(output["hole_radii"])

except Exception as e:
    output["error"] = str(e)

with open("/tmp/geometry_analysis.json", "w") as f:
    json.dump(output, f)
PYEOF

# Run the analysis script using freecadcmd (headless)
if [ "$FILE_EXISTS" = "true" ]; then
    echo "Running geometry analysis..."
    # freecadcmd might be in path, or require full path. Env uses /usr/bin/freecad usually.
    # We use 'freecadcmd' which is the console version.
    if command -v freecadcmd >/dev/null; then
        CMD="freecadcmd"
    else
        CMD="freecad --console"
    fi
    
    # Run as user ga
    su - ga -c "DISPLAY=:1 $CMD $ANALYSIS_SCRIPT" > /tmp/analysis.log 2>&1 || true
else
    # Create empty failure record
    echo '{"valid_file": false}' > "$ANALYSIS_OUTPUT"
fi

# 5. Check if App is still running
APP_RUNNING=false
if pgrep -f "freecad" > /dev/null; then
    APP_RUNNING=true
fi

# 6. Prepare Final JSON
# We merge the shell script info and the python analysis info
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $CURRENT_TIME,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "geometry_analysis": $(cat "$ANALYSIS_OUTPUT" 2>/dev/null || echo "null")
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json