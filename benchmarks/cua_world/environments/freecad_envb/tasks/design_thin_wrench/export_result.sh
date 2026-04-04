#!/bin/bash
set -e
echo "=== Exporting design_thin_wrench results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
FILE_PATH="/home/ga/Documents/FreeCAD/cone_wrench.FCStd"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check file existence and timestamp
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$FILE_PATH")
    FILE_MTIME=$(stat -c %Y "$FILE_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Geometric Analysis (Run inside container using FreeCAD's Python)
# We create a temporary python script to analyze the model geometry
cat > /tmp/analyze_wrench.py << 'PYEOF'
import FreeCAD
import Part
import sys
import json
import math

result = {
    "valid_solid": False,
    "volume": 0.0,
    "bbox_z": 0.0,
    "jaw_gap_found": False,
    "measured_gap": 0.0,
    "error": ""
}

try:
    doc = FreeCAD.openDocument("/home/ga/Documents/FreeCAD/cone_wrench.FCStd")
    
    # Find the main solid
    solid = None
    max_vol = 0
    
    for obj in doc.Objects:
        if hasattr(obj, "Shape") and obj.Shape.Solid:
             if obj.Shape.Volume > max_vol:
                 max_vol = obj.Shape.Volume
                 solid = obj.Shape

    if solid:
        result["valid_solid"] = True
        result["volume"] = solid.Volume
        result["bbox_z"] = solid.BoundBox.ZLength
        
        # Analyze faces to find jaw gap (parallel faces approx 15mm apart)
        # We look for two planar faces that are parallel, opposite, and dist ~15mm
        faces = solid.Faces
        planar_faces = [f for f in faces if str(f.Surface).startswith("<Plane")]
        
        found_gap = False
        target_gap = 15.0
        tolerance = 0.5 
        
        for i in range(len(planar_faces)):
            for j in range(i + 1, len(planar_faces)):
                f1 = planar_faces[i]
                f2 = planar_faces[j]
                
                # Check normals
                n1 = f1.normalAt(0,0)
                n2 = f2.normalAt(0,0)
                
                # Dot product should be -1 (antiparallel)
                dot = n1.dot(n2)
                if abs(dot + 1.0) < 0.01:
                    # Check distance
                    dist = f1.distToShape(f2)[0]
                    if abs(dist - target_gap) < tolerance:
                        result["jaw_gap_found"] = True
                        result["measured_gap"] = dist
                        found_gap = True
                        break
            if found_gap:
                break
                
    else:
        result["error"] = "No solid found in document"

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Run analysis if file exists
GEOMETRY_RESULT="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    echo "Running geometric analysis..."
    # We use freecadcmd (headless)
    GEOMETRY_RESULT=$(su - ga -c "freecadcmd /tmp/analyze_wrench.py" 2>/dev/null | tail -n 1)
    # Ensure we captured valid JSON
    if ! echo "$GEOMETRY_RESULT" | grep -q "^{"; then
        GEOMETRY_RESULT='{"error": "Failed to parse analysis output"}'
    fi
else
    GEOMETRY_RESULT='{"error": "File not found"}'
fi

# 4. Construct Final JSON
# Use python to merge the shell variables and the python analysis output
cat > /tmp/merge_results.py << PYEOF
import json
import sys

geo_res = json.loads(sys.argv[1])
final_res = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "geometry": geo_res,
    "screenshot_path": "/tmp/task_final.png"
}
print(json.dumps(final_res, indent=2))
PYEOF

# Save to /tmp/task_result.json
python3 /tmp/merge_results.py "$GEOMETRY_RESULT" > /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json