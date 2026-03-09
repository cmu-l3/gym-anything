#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting create_revolution results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/FreeCAD/stepped_shaft.FCStd"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check file existence and timestamps
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Run Headless FreeCAD Geometry Inspection
# We create a python script and run it with freecadcmd inside the container
# This is crucial because the host verifier cannot open .FCStd files directly
cat > /tmp/inspect_geometry.py << 'PYEOF'
import FreeCAD
import json
import math
import sys

result = {
    "valid_doc": False,
    "solid_count": 0,
    "max_volume": 0.0,
    "bbox": [0, 0, 0],
    "cylindrical_faces": 0,
    "circular_edges": 0,
    "has_revolution": False
}

try:
    doc = FreeCAD.openDocument('/home/ga/Documents/FreeCAD/stepped_shaft.FCStd')
    result["valid_doc"] = True
    
    solids = []
    for obj in doc.Objects:
        if hasattr(obj, 'Shape') and obj.Shape and not obj.Shape.isNull():
            if obj.Shape.Volume > 1.0: # Filter out construction geometry
                solids.append(obj.Shape)
    
    result["solid_count"] = len(solids)
    
    if solids:
        # Analyze the largest solid
        main_shape = max(solids, key=lambda s: s.Volume)
        result["max_volume"] = main_shape.Volume
        
        bb = main_shape.BoundBox
        # Sort dimensions to be orientation-independent
        dims = sorted([bb.XLength, bb.YLength, bb.ZLength])
        result["bbox"] = dims
        
        # Check for revolution features (cylindrical faces)
        for face in main_shape.Faces:
            surf_type = str(face.Surface)
            if 'Cylinder' in surf_type or 'Cone' in surf_type:
                result["cylindrical_faces"] += 1
        
        for edge in main_shape.Edges:
            curve_type = str(edge.Curve)
            if 'Circle' in curve_type:
                result["circular_edges"] += 1
                
        # Heuristic for revolution: has cylindrical faces OR significant circular edges
        if result["cylindrical_faces"] >= 1 or result["circular_edges"] >= 2:
            result["has_revolution"] = True

except Exception as e:
    result["error"] = str(e)

with open('/tmp/geometry_report.json', 'w') as f:
    json.dump(result, f)
PYEOF

# Run the inspection if file exists
if [ "$FILE_EXISTS" = "true" ]; then
    echo "Running geometry inspection..."
    # Try finding freecadcmd or FreeCADCmd
    CMD="freecadcmd"
    if ! command -v freecadcmd &> /dev/null; then
        CMD="FreeCADCmd"
    fi
    
    $CMD /tmp/inspect_geometry.py > /tmp/inspection.log 2>&1 || true
else
    # Create empty failure report
    echo '{"valid_doc": false, "error": "File not found"}' > /tmp/geometry_report.json
fi

# 3. Consolidate results into single JSON
# We embed the geometry report inside the main result
GEOMETRY_REPORT=$(cat /tmp/geometry_report.json 2>/dev/null || echo "{}")

cat > /tmp/task_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "geometry": $GEOMETRY_REPORT,
    "screenshot_path": "/tmp/task_final.png"
}
JSONEOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="