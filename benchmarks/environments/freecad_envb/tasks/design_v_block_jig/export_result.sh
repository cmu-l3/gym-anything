#!/bin/bash
echo "=== Exporting design_v_block_jig results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/FreeCAD/v_block.FCStd"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence & Timestamp
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

# 3. Geometric Analysis using FreeCAD Python API (Headless)
# We create a python script to inspect the model geometry
ANALYSIS_JSON="{}"

if [ "$FILE_EXISTS" = "true" ]; then
    echo "Running geometric analysis on $OUTPUT_PATH..."
    
    PYTHON_SCRIPT=$(mktemp)
    cat > "$PYTHON_SCRIPT" << EOF
import FreeCAD
import sys
import json
import math

result = {
    "valid_file": False,
    "has_solid": False,
    "bbox": [0, 0, 0],
    "volume": 0,
    "has_v_groove_faces": False,
    "has_side_slot_faces": False,
    "face_count": 0
}

try:
    doc = FreeCAD.openDocument("$OUTPUT_PATH")
    
    # Find the main solid object
    # We look for the object with the largest volume
    best_obj = None
    max_vol = 0
    
    for obj in doc.Objects:
        if hasattr(obj, 'Shape') and not obj.Shape.isNull():
            if obj.Shape.ShapeType in ['Solid', 'CompSolid']:
                vol = obj.Shape.Volume
                if vol > max_vol:
                    max_vol = vol
                    best_obj = obj
            # Also check if it's a PartDesign Body, use its tip
            elif obj.TypeId == 'PartDesign::Body':
                if obj.Tip and hasattr(obj.Tip, 'Shape') and not obj.Tip.Shape.isNull():
                    vol = obj.Tip.Shape.Volume
                    if vol > max_vol:
                        max_vol = vol
                        best_obj = obj.Tip

    if best_obj:
        shape = best_obj.Shape
        bbox = shape.BoundBox
        result["valid_file"] = True
        result["has_solid"] = True
        result["volume"] = shape.Volume
        result["bbox"] = [bbox.XLength, bbox.YLength, bbox.ZLength]
        result["face_count"] = len(shape.Faces)
        
        # Check for V-groove faces (approx 45 degrees / normals with Z ~ 0.707)
        # Normal vectors for 45 deg planes: (0.707, 0, 0.707) and (-0.707, 0, 0.707)
        v_faces_found = 0
        for f in shape.Faces:
            # Sample normal at center of face
            try:
                n = f.normalAt(0,0) # Parameter space (u,v) - simplified check
                # Better: get normal of the plane
                if hasattr(f, 'Surface') and hasattr(f.Surface, 'Axis'):
                    # For planes, normal is constant
                    # We need to check the normal direction
                    pass
            except:
                pass
            
            # Check orientation by bounding box of face or normal
            # Let's use a simpler heuristic: check for faces that are slanted
            # Check normal at center of mass of face
            try:
                center = f.CenterOfMass
                # Project center to surface to get normal
                uv = f.Surface.parameter(center)
                normal = f.normalAt(uv[0], uv[1])
                
                # Check for V-Groove normals (Z component approx 0.707)
                if 0.6 < abs(normal.z) < 0.8:
                    # Also check X component is significant
                    if 0.6 < abs(normal.x) < 0.8:
                         v_faces_found += 1
            except:
                pass
        
        if v_faces_found >= 2:
            result["has_v_groove_faces"] = True
            
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

    # Run the script using freecadcmd
    # Capture only the last line which should be the JSON
    ANALYSIS_OUTPUT=$(freecadcmd "$PYTHON_SCRIPT" 2>/dev/null | tail -n 1)
    
    # Verify if output is valid JSON
    if echo "$ANALYSIS_OUTPUT" | jq . >/dev/null 2>&1; then
        ANALYSIS_JSON="$ANALYSIS_OUTPUT"
    else
        echo "Failed to parse analysis output: $ANALYSIS_OUTPUT"
        ANALYSIS_JSON="{\"error\": \"Analysis script failed\", \"raw_output\": \"$ANALYSIS_OUTPUT\"}"
    fi
    
    rm -f "$PYTHON_SCRIPT"
fi

# 4. Compile Final JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "analysis": $ANALYSIS_JSON
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="