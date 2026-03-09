#!/bin/bash
echo "=== Exporting design_robot_gripper_finger result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_FILE="/home/ga/Documents/FreeCAD/gripper_finger.FCStd"

# 1. Check file existence and timestamp
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check if App is running
APP_RUNNING=$(pgrep -f "freecad" > /dev/null && echo "true" || echo "false")

# 3. Geometry Analysis using FreeCAD Python (Headless)
# We create a python script to run inside the environment to inspect the geometry
cat > /tmp/inspect_geometry.py << 'PYEOF'
import FreeCAD
import Part
import json
import sys
import math

result = {
    "valid_solid": False,
    "bbox": [0, 0, 0],
    "volume": 0,
    "holes_detected": False,
    "groove_detected": False,
    "features_score": 0,
    "error": ""
}

try:
    doc_path = "/home/ga/Documents/FreeCAD/gripper_finger.FCStd"
    try:
        doc = FreeCAD.openDocument(doc_path)
    except Exception as e:
        result["error"] = f"Could not open document: {str(e)}"
        print(json.dumps(result))
        sys.exit(0)

    if not doc.Objects:
        result["error"] = "Empty document"
        print(json.dumps(result))
        sys.exit(0)

    # Find the solid
    solid = None
    for obj in doc.Objects:
        # Check for Part::Feature (common base) and Shape attribute
        if hasattr(obj, "Shape") and obj.Shape.ShapeType == "Solid":
            solid = obj.Shape
            break
        # Also check for PartDesign::Body
        if obj.TypeId == "PartDesign::Body":
             if hasattr(obj, "Shape") and obj.Shape.ShapeType == "Solid":
                solid = obj.Shape
                break

    if solid:
        result["valid_solid"] = True
        
        # BBox
        bbox = solid.BoundBox
        result["bbox"] = [bbox.XLength, bbox.YLength, bbox.ZLength]
        
        # Volume
        result["volume"] = solid.Volume
        
        # Feature Analysis
        hole_faces = 0
        groove_faces = 0
        
        for face in solid.Faces:
            try:
                surf = face.Surface
                surf_type = type(surf).__name__
                
                # Check for holes (Cylinders at X=15)
                if surf_type == "Cylinder":
                    # Center of cylinder axis
                    if hasattr(surf, "Center"):
                        u, v, w = surf.Center
                        r = surf.Radius
                        # X should be around 15, Y around +/- 8
                        if abs(u - 15) < 5 and (abs(v - 8) < 5 or abs(v + 8) < 5):
                            # Radius 2.75 (5.5mm hole) or 5.0 (10mm cbore)
                            if abs(r - 2.75) < 0.2 or abs(r - 5.0) < 0.2:
                                hole_faces += 1
                
                # Check for groove (Planes at X=85 with specific normal)
                elif surf_type == "Plane":
                    # Get center of face to check position
                    bbox_f = face.BoundBox
                    cx = bbox_f.Center.x
                    
                    if abs(cx - 85) < 10:
                        # Check normal at center
                        uv = face.Surface.parameter(bbox_f.Center)
                        norm = face.normalAt(uv[0], uv[1])
                        
                        # Normal should have Y component (facing in/out of Y axis) 
                        # and Z component 0 (vertical walls)
                        # Groove sides are 45 deg to Y axis.
                        # Normals: (+/- sin45, +/- cos45, 0) approx
                        if abs(norm.z) < 0.1 and abs(norm.y) > 0.4 and abs(norm.y) < 0.9:
                            groove_faces += 1
            except Exception:
                continue

        if hole_faces >= 2:
            result["holes_detected"] = True
        
        if groove_faces >= 2:
            result["groove_detected"] = True
            
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Run the python script using freecadcmd
if [ "$FILE_EXISTS" = "true" ]; then
    echo "Running geometry analysis..."
    # freecadcmd is the headless version
    GEOMETRY_JSON=$(su - ga -c "freecadcmd /tmp/inspect_geometry.py" | tail -n 1)
else
    GEOMETRY_JSON='{"valid_solid": false, "error": "File not found"}'
fi

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create final result JSON
# We embed the geometry analysis JSON inside our result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "geometry_analysis": $GEOMETRY_JSON
}
EOF

# Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="