#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting create_vgroove_pulley results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FCSTD_FILE="/home/ga/Documents/FreeCAD/vgroove_pulley.FCStd"
STEP_FILE="/home/ga/Documents/FreeCAD/vgroove_pulley.step"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check files
FCSTD_EXISTS="false"
FCSTD_SIZE=0
FCSTD_VALID_TIME="false"
if [ -f "$FCSTD_FILE" ]; then
    FCSTD_EXISTS="true"
    FCSTD_SIZE=$(stat -c%s "$FCSTD_FILE")
    F_TIME=$(stat -c%Y "$FCSTD_FILE")
    if [ "$F_TIME" -ge "$TASK_START" ]; then
        FCSTD_VALID_TIME="true"
    fi
fi

STEP_EXISTS="false"
STEP_SIZE=0
STEP_VALID_TIME="false"
if [ -f "$STEP_FILE" ]; then
    STEP_EXISTS="true"
    STEP_SIZE=$(stat -c%s "$STEP_FILE")
    S_TIME=$(stat -c%Y "$STEP_FILE")
    if [ "$S_TIME" -ge "$TASK_START" ]; then
        STEP_VALID_TIME="true"
    fi
fi

# Run geometric analysis inside the container using FreeCAD's Python API
# We output a JSON structure to stdout
echo "Running geometric analysis..."
ANALYSIS_JSON=$(python3 - << 'PY_EOF' 2>/dev/null || echo '{"error": "Analysis failed"}'
import sys
import json
import math

try:
    # Add FreeCAD paths
    sys.path.append('/usr/lib/freecad/lib')
    import FreeCAD

    file_path = "/home/ga/Documents/FreeCAD/vgroove_pulley.FCStd"
    result = {
        "valid_solid": False,
        "volume": 0.0,
        "bbox": [0.0, 0.0, 0.0],
        "has_bore": False,
        "has_groove_indicative_volume": False,
        "error": None
    }

    try:
        doc = FreeCAD.openDocument(file_path)
    except Exception:
        result["error"] = "Could not open document"
        print(json.dumps(result))
        sys.exit(0)

    # Find the visible solid
    target_shape = None
    for obj in doc.Objects:
        if hasattr(obj, 'Shape') and obj.Shape.isValid():
             # Check if it has volume (some helper objects don't)
             if obj.Shape.Volume > 1000:
                 target_shape = obj.Shape
                 # Don't break immediately, prefer the last modified or largest? 
                 # Usually the last feature in PartDesign is the valid one.
    
    if target_shape:
        result["valid_solid"] = True
        result["volume"] = target_shape.Volume
        
        # Bounding Box
        bb = target_shape.BoundBox
        dims = sorted([bb.XLength, bb.YLength, bb.ZLength])
        result["bbox"] = dims
        
        # Check for Bore: Look for a cylindrical face with Radius approx 4mm
        for face in target_shape.Faces:
            try:
                surf = face.Surface
                # Check class name string to avoid import issues
                if "Cylinder" in str(type(surf)):
                    if 3.9 <= surf.Radius <= 4.1:
                        result["has_bore"] = True
                        break
            except:
                pass
        
        # Check for Groove via volume logic
        # Plain cylinder 60x15 minus 8mm bore volume:
        # V = pi * (30^2 - 4^2) * 15 = pi * 884 * 15 approx 41657
        # Expected groove removes approx 2000-3000 mm3
        # If volume is significantly less than 41000, groove exists
        if result["volume"] < 41000 and result["volume"] > 35000:
             result["has_groove_indicative_volume"] = True

    else:
        result["error"] = "No valid solid shape found"

    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e)}))
PY_EOF
)

# Construct final JSON result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "fcstd_exists": $FCSTD_EXISTS,
    "fcstd_size": $FCSTD_SIZE,
    "fcstd_valid_time": $FCSTD_VALID_TIME,
    "step_exists": $STEP_EXISTS,
    "step_size": $STEP_SIZE,
    "step_valid_time": $STEP_VALID_TIME,
    "analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="