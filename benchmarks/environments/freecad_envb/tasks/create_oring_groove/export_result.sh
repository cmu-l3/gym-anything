#!/bin/bash
set -e
echo "=== Exporting create_oring_groove results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/Documents/FreeCAD/shaft_with_groove.FCStd"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file metadata
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$TARGET_FILE")
    FILE_MTIME=$(stat -c%Y "$TARGET_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Run geometric analysis using FreeCAD's internal Python
# We write a python script to a temp file and execute it with freecadcmd or python3 (if libraries linked)
# Note: In this env, we can usually import FreeCAD in python3 if paths are set, or use `freecadcmd`

cat > /tmp/analyze_geometry.py << 'PYEOF'
import sys
import json
import os

# Setup FreeCAD paths (common locations)
sys.path.append('/usr/lib/freecad/lib')
sys.path.append('/usr/lib/freecad-python3/lib')

try:
    import FreeCAD
    import Part
except ImportError:
    print(json.dumps({"error": "FreeCAD module not found"}))
    sys.exit(0)

target_file = "/home/ga/Documents/FreeCAD/shaft_with_groove.FCStd"
result = {
    "valid_fcstd": False,
    "features": [],
    "volume": 0.0,
    "bbox": [0.0, 0.0, 0.0],
    "groove_check": False,
    "error": None
}

if not os.path.exists(target_file):
    print(json.dumps(result))
    sys.exit(0)

try:
    doc = FreeCAD.openDocument(target_file)
    result["valid_fcstd"] = True
    
    # Analyze Feature Tree
    for obj in doc.Objects:
        # Check for PartDesign features
        type_str = obj.TypeId
        # Store simplified type info
        if "Pad" in type_str:
            result["features"].append("Pad")
        elif "Groove" in type_str:
            result["features"].append("Groove")
        elif "Body" in type_str:
            result["features"].append("Body")
        elif "Sketch" in type_str:
            result["features"].append("Sketch")
            
    # Analyze Geometry (Find the main solid)
    # Usually the Body object or the last feature has the final shape
    final_shape = None
    
    # Strategy: Look for the Body's Shape
    bodies = [obj for obj in doc.Objects if obj.TypeId == 'PartDesign::Body']
    if bodies:
        final_shape = bodies[0].Shape
    else:
        # Fallback: find any solid with volume
        for obj in doc.Objects:
            if hasattr(obj, "Shape") and obj.Shape.Solid:
                final_shape = obj.Shape
                break
    
    if final_shape:
        result["volume"] = final_shape.Volume
        bb = final_shape.BoundBox
        result["bbox"] = [bb.XLength, bb.YLength, bb.ZLength]
        
        # Specific Check: Groove existence via cross-section area
        # Cut at Z=15 (groove center) and Z=30 (solid shaft)
        # Z=15 should have smaller area or multiple edges if it's an annulus
        # Shaft R=10 => Area = 314.15
        # Groove R_inner=8.5 => Area = 226.98
        
        slice_groove = final_shape.makeSection(FreeCAD.Vector(0,0,15), FreeCAD.Vector(0,0,1))
        slice_solid = final_shape.makeSection(FreeCAD.Vector(0,0,30), FreeCAD.Vector(0,0,1))
        
        area_groove = slice_groove.Area
        area_solid = slice_solid.Area
        
        # If slice is wires, Area might be 0 in some versions, check lengths/edges
        if area_groove < area_solid * 0.9:
            result["groove_check"] = True
        elif len(slice_groove.Edges) > len(slice_solid.Edges):
             # Annulus has 2 circles, solid has 1
            result["groove_check"] = True
            
    else:
        result["error"] = "No solid shape found"

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Execute analysis
GEOMETRY_JSON="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    # Try running with python3 (assuming env paths set in script) or freecadcmd
    # We'll try python3 first as it's cleaner for json output
    if python3 /tmp/analyze_geometry.py > /tmp/geo_out.json 2>/dev/null; then
        GEOMETRY_JSON=$(cat /tmp/geo_out.json)
    else
        GEOMETRY_JSON="{\"error\": \"Analysis script failed\"}"
    fi
fi

# Compile final result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "geometry_analysis": $GEOMETRY_JSON
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json