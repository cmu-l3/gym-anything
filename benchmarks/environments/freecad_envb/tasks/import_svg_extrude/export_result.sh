#!/bin/bash
set -e
echo "=== Exporting import_svg_extrude results ==="

source /workspace/scripts/task_utils.sh

OUTPUT_FILE="/home/ga/Documents/FreeCAD/sensor_mount.FCStd"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_JSON="/tmp/task_result.json"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check file metadata
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Perform Geometry Analysis INSIDE container (using FreeCAD Python API)
# We must generate this JSON here because verifier.py cannot run freecadcmd
echo "Running FreeCAD geometry analysis..."

cat > /tmp/analyze_geometry.py << 'PYEOF'
import sys
import json
import FreeCAD

results = {
    "valid_doc": False,
    "has_solid": False,
    "bbox_x": 0.0,
    "bbox_y": 0.0,
    "bbox_z": 0.0,
    "volume": 0.0,
    "num_shapes": 0
}

try:
    if len(sys.argv) > 1:
        filepath = sys.argv[1]
        doc = FreeCAD.openDocument(filepath)
        results["valid_doc"] = True
        
        # Find best solid candidate
        best_solid = None
        max_vol = 0.0
        
        for obj in doc.Objects:
            if hasattr(obj, 'Shape') and obj.Shape is not None:
                results["num_shapes"] += 1
                shape = obj.Shape
                
                # Check for Solid or Compound containing solids
                if shape.ShapeType in ['Solid', 'CompSolid', 'Compound']:
                    vol = shape.Volume
                    if vol > max_vol:
                        max_vol = vol
                        best_solid = shape
                        
                        # Verify it has solid topology
                        if shape.ShapeType == 'Solid' or (hasattr(shape, 'Solids') and len(shape.Solids) > 0):
                            results["has_solid"] = True

        if best_solid:
            bb = best_solid.BoundBox
            results["bbox_x"] = bb.XLength
            results["bbox_y"] = bb.YLength
            results["bbox_z"] = bb.ZLength
            results["volume"] = best_solid.Volume
            
except Exception as e:
    results["error"] = str(e)

with open("/tmp/geometry_analysis.json", "w") as f:
    json.dump(results, f)
PYEOF

if [ "$FILE_EXISTS" = "true" ]; then
    # Run the python script using freecadcmd
    freecadcmd /tmp/analyze_geometry.py "$OUTPUT_FILE" > /tmp/analysis.log 2>&1 || true
else
    # Create empty results if file missing
    echo '{"valid_doc": false}' > /tmp/geometry_analysis.json
fi

# 4. Compile all results into final JSON
# Use python to merge metadata and geometry analysis safely
python3 -c "
import json
import os

try:
    # Load geometry results
    if os.path.exists('/tmp/geometry_analysis.json'):
        with open('/tmp/geometry_analysis.json') as f:
            geo = json.load(f)
    else:
        geo = {}

    final = {
        'task_start': $TASK_START,
        'output_exists': $FILE_EXISTS,
        'file_created_during_task': $FILE_CREATED_DURING_TASK,
        'file_size_bytes': $FILE_SIZE,
        'geometry': geo
    }
    
    with open('$RESULTS_JSON', 'w') as f:
        json.dump(final, f, indent=2)
        
except Exception as e:
    print(f'Error creating result JSON: {e}')
"

# Set permissions for copy_from_env
chmod 644 "$RESULTS_JSON" 2>/dev/null || true
chmod 644 /tmp/task_final.png 2>/dev/null || true

echo "=== Export complete ==="
cat "$RESULTS_JSON"