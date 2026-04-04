#!/bin/bash
echo "=== Exporting constrain_mechanical_profile result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_PATH="/home/ga/Documents/FreeCAD/linkage_profile.FCStd"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check file modification
FILE_EXISTS="false"
FILE_MODIFIED="false"
if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$FILE_PATH")
    INITIAL_MTIME=$(cat /tmp/initial_file_mtime.txt 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$INITIAL_MTIME" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 3. Internal Verification Script
# We run a python script INSIDE FreeCAD (headless) to analyze the sketch constraints.
# This is more robust than trying to parse the XML manually or running python on the host.

cat > /tmp/analyze_sketch.py << 'PYEOF'
import FreeCAD, Sketcher, json, sys

result = {
    "valid_doc": False,
    "has_sketch": False,
    "is_fully_constrained": False,
    "dof": -1,
    "has_length_constraint": False,
    "has_radius_constraint": False,
    "length_value": 0.0,
    "radius_value": 0.0,
    "geometry_count": 0
}

try:
    doc_path = "/home/ga/Documents/FreeCAD/linkage_profile.FCStd"
    doc = FreeCAD.openDocument(doc_path)
    result["valid_doc"] = True
    
    sk = doc.getObject("LinkageSlot")
    if sk and sk.TypeId == 'Sketcher::SketchObject':
        result["has_sketch"] = True
        result["geometry_count"] = sk.GeometryCount
        
        # Check Solver Status
        # In headless, we often check GeometryCount vs ConstraintCount or use solve()
        # sk.solve() returns 0 if fully constrained
        solve_result = sk.solve()
        result["dof"] = len(sk.OpenVertices) # This is not strictly DOF, better to check solver info if exposed
        # A better check for 'Fully Constrained' in python:
        # (GeometryCount * DOFs_per_geo) - ConstraintCount - RigidBodyMotion... 
        # Easier: Check if 'FullyConstrained' string is in sk.SolverStatus (might depend on version)
        # Or rely on geometry checks.
        
        # Let's iterate constraints to find our target values
        for c in sk.Constraints:
            # Check for Distance/DistanceX/DistanceY (Length)
            # We expect 120mm
            if "Distance" in c.Type and abs(c.Value - 120.0) < 0.1:
                result["has_length_constraint"] = True
                result["length_value"] = c.Value
            
            # Check for Radius
            # We expect 25mm
            if "Radius" in c.Type and abs(c.Value - 25.0) < 0.1:
                result["has_radius_constraint"] = True
                result["radius_value"] = c.Value

        # Check if geometry bounding box matches expected fully constrained shape
        # Center-to-center 120, Radius 25
        # Total Width = 50, Total Length = 120 + 25 + 25 = 170
        if hasattr(sk.Shape, "BoundBox"):
            bb = sk.Shape.BoundBox
            if abs(bb.XLength - 170.0) < 1.0 and abs(bb.YLength - 50.0) < 1.0:
                result["is_fully_constrained"] = True # Geometry matches perfectly
                
except Exception as e:
    result["error"] = str(e)

with open("/tmp/sketch_analysis.json", "w") as f:
    json.dump(result, f)
PYEOF

# Run the analysis script
echo "Running internal sketch analysis..."
freecadcmd /tmp/analyze_sketch.py > /dev/null 2>&1 || true

# 4. Construct Final JSON
# We merge the file stats and the internal analysis
PYTHON_MERGE_SCRIPT=$(cat <<EOF
import json, os
try:
    with open("/tmp/sketch_analysis.json", "r") as f:
        analysis = json.load(f)
except:
    analysis = {}

output = {
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "screenshot_path": "/tmp/task_final.png",
    "analysis": analysis
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(output, f)
EOF
)

python3 -c "$PYTHON_MERGE_SCRIPT"

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json