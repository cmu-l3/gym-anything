#!/bin/bash
echo "=== Exporting modify_bearing_housing_eco results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/FreeCAD/modified_housing.FCStd"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file existence and timestamps
OUTPUT_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    # Check if file was modified after task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Check if hash differs from original (did they actually change anything?)
    CURRENT_HASH=$(md5sum "$OUTPUT_FILE" | awk '{print $1}')
    INITIAL_HASH=$(cat /tmp/initial_file_hash.txt 2>/dev/null || echo "")
    
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        HASH_CHANGED="true"
    else
        HASH_CHANGED="false"
    fi
else
    HASH_CHANGED="false"
fi

# ------------------------------------------------------------------
# GEOMETRY ANALYSIS (Running headless FreeCAD inside container)
# ------------------------------------------------------------------
# We use FreeCAD's Python API to inspect the geometry of the saved file.
# This avoids needing complex geometry libraries on the verifier host.

ANALYSIS_JSON="/tmp/geometry_analysis.json"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Running geometry analysis on $OUTPUT_FILE..."
    
    cat > /tmp/analyze_geometry.py << PYEOF
import FreeCAD
import Part
import json
import sys

output_path = "$ANALYSIS_JSON"
file_path = "$OUTPUT_FILE"

result = {
    "success": False,
    "error": "",
    "bbox": [0, 0, 0],
    "cylindrical_faces": [],
    "volume": 0
}

try:
    # Open document without GUI
    doc = FreeCAD.openDocument(file_path)
    
    # Find the visible solid (likely the last modified object or the one named 'Body')
    target_shape = None
    
    # Strategy 1: Look for PartDesign Body
    bodies = [obj for obj in doc.Objects if 'Body' in obj.TypeId]
    if bodies:
        target_shape = bodies[0].Shape
    
    # Strategy 2: Look for any solid if no Body found
    if not target_shape:
        for obj in doc.Objects:
            if hasattr(obj, 'Shape') and obj.Shape.Solid:
                target_shape = obj.Shape
                break
    
    if target_shape:
        result["success"] = True
        
        # Bounding Box
        bbox = target_shape.BoundBox
        result["bbox"] = [bbox.XLength, bbox.YLength, bbox.ZLength]
        result["volume"] = target_shape.Volume
        
        # Analyze Faces for Holes
        # We look for cylindrical faces (internal or external)
        diameters = []
        for face in target_shape.Faces:
            surf = face.Surface
            # Check if surface is cylindrical
            if "Cylinder" in str(type(surf)):
                # Diameter = Radius * 2
                d = surf.Radius * 2
                diameters.append(round(d, 3))
        
        result["cylindrical_faces"] = sorted(diameters)
    else:
        result["error"] = "No solid geometry found in file"

except Exception as e:
    result["error"] = str(e)

with open(output_path, 'w') as f:
    json.dump(result, f)
PYEOF

    # Run the analysis script using freecadcmd (headless)
    # We use 'su - ga' to ensure permissions match, but map display just in case
    # explicit path to python library might be needed depending on install, 
    # but freecadcmd sets up the path.
    DISPLAY=:1 freecadcmd /tmp/analyze_geometry.py > /tmp/analysis.log 2>&1 || true
else
    echo "{"success": false, "error": "File not found"}" > "$ANALYSIS_JSON"
fi

# Merge results into final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "hash_changed": $HASH_CHANGED,
    "file_size": $FILE_SIZE,
    "geometry_analysis": $(cat "$ANALYSIS_JSON" 2>/dev/null || echo "{}"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save final result
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="