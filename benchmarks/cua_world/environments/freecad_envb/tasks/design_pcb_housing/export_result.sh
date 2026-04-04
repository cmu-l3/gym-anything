#!/bin/bash
echo "=== Exporting design_pcb_housing result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/FreeCAD/pcb_housing.FCStd"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if file exists
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    # Run internal geometric analysis using FreeCAD's Python API
    # We write a script to run inside the container's FreeCAD environment
    cat > /tmp/analyze_geometry.py << 'PYEOF'
import FreeCAD
import json
import sys
import math

result = {
    "valid_file": False,
    "solid_found": False,
    "bbox": [0, 0, 0],
    "volume": 0,
    "cylindrical_faces": 0,
    "has_side_cutout": False,
    "error": ""
}

try:
    doc = FreeCAD.openDocument("/home/ga/Documents/FreeCAD/pcb_housing.FCStd")
    
    # Find the main solid (usually the Tip of a Body or the largest object)
    solid = None
    max_vol = 0
    
    for obj in doc.Objects:
        if hasattr(obj, 'Shape') and obj.Shape.Volume > 1000: # Filter out datum planes etc
             if obj.Shape.Volume > max_vol:
                 max_vol = obj.Shape.Volume
                 solid = obj.Shape

    if solid:
        result["valid_file"] = True
        result["solid_found"] = True
        result["volume"] = solid.Volume
        bbox = solid.BoundBox
        result["bbox"] = [bbox.XLength, bbox.YLength, bbox.ZLength]
        
        # Analyze faces
        cylinders = 0
        for face in solid.Faces:
            surf = face.Surface
            # FreeCAD surface types: Part.Plane, Part.Cylinder, etc.
            if "Cylinder" in str(type(surf)):
                cylinders += 1
        result["cylindrical_faces"] = cylinders
        
        # Check for cutout on the Right Face (X max approx 50 or 100 depending on origin)
        # We look for faces that are NOT on the bounding box limits
        # Actually, simpler check: Bounding box of the solid should match, 
        # but volume should be less than a solid block.
        # Specific check for cutout: Cast a ray or check if point is inside?
        # Let's check if the bounding box of the material is correct.
        
        # Check if point where cutout should be is empty (False)
        # Cutout center approx: X=50 (wall), Y=0 (center), Z=5+6=11 (bottom 5 + half height 6)
        # We need to account for coordinate system. 
        # Assuming box is centered or cornered. 
        # The prompt said 100x60x30. 
        # If centered: X in [-50, 50]. Cutout on X=50 face.
        # If cornered: X in [0, 100]. Cutout on X=100 face.
        # We can detect positioning from bbox.
        
        # We will leave strict positional check to the "volume" metric which captures cutouts well.
        # But we can check surface area to see if there are extra internal faces.
        pass

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

    # Execute analysis
    # Use freecadcmd (headless)
    ANALYSIS_JSON=$(su - ga -c "DISPLAY=:1 freecadcmd /tmp/analyze_geometry.py 2>/dev/null" | grep -v "FreeCAD")
    # If freecadcmd outputs header noise, we might need to filter.
    # Usually the last line is our print.
    ANALYSIS_JSON=$(echo "$ANALYSIS_JSON" | tail -n 1)

else
    OUTPUT_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
    OUTPUT_SIZE="0"
    ANALYSIS_JSON="{}"
fi

# Create final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "geometry_analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="