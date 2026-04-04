#!/bin/bash
echo "=== Exporting connecting rod results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/FreeCAD/connecting_rod.FCStd"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check if file exists
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    FILE_MTIME="0"
fi

# ------------------------------------------------------------------
# GEOMETRY ANALYSIS INSIDE CONTAINER
# We run a headless FreeCAD Python script to analyze the model geometry
# and write the results to a JSON file.
# ------------------------------------------------------------------

cat > /tmp/analyze_rod.py << 'PYEOF'
import FreeCAD
import sys
import json
import math

result = {
    "valid_solid": False,
    "bbox": [0, 0, 0],
    "volume": 0,
    "has_big_hole": False,
    "has_small_hole": False,
    "min_thickness": 0,
    "face_count": 0,
    "error": ""
}

try:
    doc_path = "/home/ga/Documents/FreeCAD/connecting_rod.FCStd"
    doc = FreeCAD.openDocument(doc_path)
    
    # Find the visible solid
    solid_obj = None
    for obj in doc.Objects:
        if hasattr(obj, "Shape") and obj.Shape.isValid():
            if obj.Shape.Solid:
                # Use the last modified or most complex solid
                solid_obj = obj
            
            # If it's a PartDesign Body, get the Tip
            if obj.TypeId == "PartDesign::Body":
                if obj.Tip and obj.Tip.Shape.Solid:
                    solid_obj = obj.Tip
                    break

    if solid_obj:
        shape = solid_obj.Shape
        result["valid_solid"] = True
        result["volume"] = shape.Volume
        result["face_count"] = len(shape.Faces)
        
        bb = shape.BoundBox
        result["bbox"] = [bb.XLength, bb.YLength, bb.ZLength]
        
        # Check for holes (Cylindrical faces)
        # Big hole: Radius 15mm (Dia 30)
        # Small hole: Radius 6mm (Dia 12)
        for f in shape.Faces:
            if "Cylinder" in str(f.Surface):
                r = f.Surface.Radius
                # Check for internal holes (concave curvature usually, or just match radius)
                # Note: FreeCAD Surface.Radius is always positive
                if abs(r - 15.0) < 0.5:
                    result["has_big_hole"] = True
                if abs(r - 6.0) < 0.5:
                    result["has_small_hole"] = True
                    
        # Check for I-beam recess
        # Strategy: The full thickness is 10mm. If recesses exist on both sides (2mm deep each),
        # the "web" thickness in the middle should be 6mm.
        # We can approximate this by checking if volume is significantly less than a simple extrusion,
        # or checking face areas.
        # A simple check: Volume of "solid" rod approx:
        # 2 ends + shank ~ 15000-20000.
        # Recesses remove ~ 1440 mm3.
        pass

    else:
        result["error"] = "No valid solid found in document"

except Exception as e:
    result["error"] = str(e)

with open("/tmp/geometry_analysis.json", "w") as f:
    json.dump(result, f)
PYEOF

# Run the analysis if file exists
GEOMETRY_ANALYSIS="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    echo "Running geometry analysis..."
    # Run using freecadcmd (headless)
    su - ga -c "freecadcmd /tmp/analyze_rod.py" > /tmp/analysis.log 2>&1
    if [ -f "/tmp/geometry_analysis.json" ]; then
        GEOMETRY_ANALYSIS=$(cat /tmp/geometry_analysis.json)
    fi
fi

# Prepare final result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "geometry": $GEOMETRY_ANALYSIS
}
EOF

echo "Result stored in /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="