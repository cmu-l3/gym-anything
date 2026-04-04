#!/bin/bash
echo "=== Exporting create_manifold_block results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/FreeCAD/manifold_block.FCStd"

# 1. Check file existence and timestamp
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
    OUTPUT_SIZE="0"
fi

# 2. Run In-Container Geometry Analysis using FreeCAD's Python API
# We create a temporary python script and run it with freecadcmd
if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Running geometry analysis..."
    cat > /tmp/analyze_manifold.py << 'PYEOF'
import FreeCAD
import Part
import json
import sys
import math

output_file = "/tmp/geometry_analysis.json"
result = {
    "success": False, 
    "volume": 0, 
    "expected_volume": 0,
    "bbox": [0,0,0], 
    "error": ""
}

try:
    # Open the user's file
    doc = FreeCAD.open(sys.argv[1])
    
    # Find the final solid
    # We look for the visible object with the largest volume (likely the result)
    best_solid = None
    max_vol = 0
    
    for obj in doc.Objects:
        if hasattr(obj, 'Shape') and hasattr(obj.Shape, 'Volume') and obj.Shape.Volume > 1000:
            # Check if it's visible (heuristic) or just take the last one created
            if obj.Shape.Volume > max_vol:
                max_vol = obj.Shape.Volume
                best_solid = obj.Shape

    if best_solid:
        # Calculate Reference Volume Programmatically
        # Reference: Box 60x60x60 minus 3 orthogonal cylinders (r=10)
        # We construct the reference shape to get the EXACT expected volume for comparison
        # This handles the complex intersections of the cylinders correctly.
        
        ref_box = Part.makeBox(60, 60, 60)
        # Center the cylinders relative to the box 
        # (Assuming box at 0,0,0 -> 60,60,60, center is 30,30,30)
        c_z = Part.makeCylinder(10, 60, FreeCAD.Vector(30,30,0), FreeCAD.Vector(0,0,1))
        c_x = Part.makeCylinder(10, 60, FreeCAD.Vector(0,30,30), FreeCAD.Vector(1,0,0))
        c_y = Part.makeCylinder(10, 60, FreeCAD.Vector(30,0,30), FreeCAD.Vector(0,1,0))
        
        ref_shape = ref_box.cut(c_z).cut(c_x).cut(c_y)
        
        result["success"] = True
        result["volume"] = best_solid.Volume
        result["expected_volume"] = ref_shape.Volume
        result["bbox"] = [
            best_solid.BoundBox.XLength,
            best_solid.BoundBox.YLength,
            best_solid.BoundBox.ZLength
        ]
        result["solid_type"] = best_solid.ShapeType
    else:
        result["error"] = "No significant solid found in document"

except Exception as e:
    result["error"] = str(e)

with open(output_file, 'w') as f:
    json.dump(result, f)
PYEOF

    # Run the script using freecadcmd (headless)
    # We rely on system path or absolute path. Usually /usr/bin/freecadcmd
    CMD="freecadcmd"
    if [ -f "/usr/lib/freecad/bin/freecadcmd" ]; then
        CMD="/usr/lib/freecad/bin/freecadcmd"
    fi
    
    $CMD /tmp/analyze_manifold.py "$OUTPUT_PATH" > /tmp/analysis.log 2>&1
else
    echo '{"success": false, "error": "File not found"}' > /tmp/geometry_analysis.json
fi

# 3. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Construct final JSON result
# Merge geometry analysis with file stats
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
try:
    with open('/tmp/geometry_analysis.json') as f:
        geo = json.load(f)
except:
    geo = {}

res = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'output_exists': '$OUTPUT_EXISTS' == 'true',
    'file_created_during_task': '$FILE_CREATED_DURING_TASK' == 'true',
    'output_size_bytes': $OUTPUT_SIZE,
    'geometry': geo,
    'screenshot_path': '/tmp/task_final.png'
}
print(json.dumps(res))
" > "$TEMP_JSON"

# Move to standard location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="