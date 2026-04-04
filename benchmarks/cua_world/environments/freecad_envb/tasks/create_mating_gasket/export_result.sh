#!/bin/bash
echo "=== Exporting create_mating_gasket results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot (desktop state)
take_screenshot /tmp/task_final.png

# 2. Basic file checks
OUTPUT_PATH="/home/ga/Documents/FreeCAD/T8_gasket.FCStd"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. ADVANCED: Run Headless FreeCAD Geometry Analysis
# We create a python script to run INSIDE the container's FreeCAD environment
# This allows us to query the actual geometry kernel.

ANALYSIS_SCRIPT="/tmp/analyze_gasket.py"
cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import FreeCAD
import Part
import json
import sys
import math

result = {
    "valid_file": False,
    "new_body_found": False,
    "gasket_volume": 0.0,
    "gasket_thickness": 0.0,
    "holes_found": 0,
    "holes_aligned": False,
    "alignment_error_max": 999.0,
    "error": ""
}

try:
    # Open the file
    doc_path = "/home/ga/Documents/FreeCAD/T8_gasket.FCStd"
    try:
        doc = FreeCAD.openDocument(doc_path)
    except Exception as e:
        result["error"] = f"Could not open document: {str(e)}"
        print(json.dumps(result))
        sys.exit(0)

    result["valid_file"] = True
    
    # Identify bodies
    # Expected: The original bracket (usually named 'Body' or 'T8_housing_bracket') 
    # and a NEW body for the gasket.
    
    bodies = []
    for obj in doc.Objects:
        if obj.TypeId == 'PartDesign::Body' or obj.isDerivedFrom('Part::Feature'):
            # We look for solids
            if hasattr(obj, 'Shape') and not obj.Shape.isNull() and obj.Shape.Volume > 10:
                bodies.append(obj)
    
    # We expect the original bracket has a volume ~24000 mm^3 (approx for T8)
    # The gasket should be much smaller, ~2mm thick * footprint.
    # Footprint approx 40mm x 30mm minus holes ~ 1000 mm^2. Volume ~ 2000 mm^3.
    
    gasket_candidate = None
    original_bracket = None
    
    for b in bodies:
        vol = b.Shape.Volume
        # T8 bracket is approx 24,000 mm3
        # Gasket (2mm thick) should be approx 2,000 - 4,000 mm3
        if 1000 < vol < 6000:
            gasket_candidate = b
        elif vol > 10000:
            original_bracket = b
            
    if gasket_candidate:
        result["new_body_found"] = True
        shape = gasket_candidate.Shape
        result["gasket_volume"] = shape.Volume
        
        # Check thickness (Bounding Box Z)
        # Note: This depends on orientation, but usually T8 sits on XY or XZ.
        # We check the smallest dimension of the bounding box.
        bbox = shape.BoundBox
        dims = [bbox.XLength, bbox.YLength, bbox.ZLength]
        dims.sort()
        result["gasket_thickness"] = dims[0] # Smallest dim is likely thickness
        
        # Check holes alignment
        # We slice the gasket in the middle of its thickness to find holes
        # Assuming it's on a plane, a slice will return a face with wires.
        
        # Create a slice at the center of the bounding box
        center = bbox.Center
        # We don't know the axis, so we try slicing normal to the smallest dimension
        # Actually, simpler: check for cylindrical faces with specific radii
        
        hole_centers = []
        for f in shape.Faces:
            surf = f.Surface
            # Look for cylindrical faces (holes)
            if hasattr(surf, 'Radius'):
                # M5 holes are usually 5.5mm or similar in bracket (Radius ~2.75)
                # T8 mounting holes usually ~5mm dia or 4mm dia.
                if 1.5 < surf.Radius < 3.5: # 3mm to 7mm diameter holes
                    # It's a hole candidate. Get axis/center.
                    # Axis of cylinder
                    axis = surf.Axis
                    center = surf.Center
                    # Project center to 2D plane to compare layout? 
                    # Actually, we just need to count them and check spacing.
                    
                    # Deduplicate: Cylinders have a length, might be detected multiple times or split faces
                    # We store centers.
                    is_new = True
                    for ec in hole_centers:
                        dist = ec.sub(center).Length
                        if dist < 0.1: is_new = False
                        # Also check if it's the same hole but just different height along axis
                        # Project onto perpendicular plane
                        
                    if is_new:
                        hole_centers.append(center)

        # Refined hole counting: The gasket should have 4 mount holes.
        # Let's count wires in a cross section. 
        # But simply counting cylindrical faces of correct size is often enough proxy.
        # A 2mm plate with 4 holes will have 4 cylindrical faces (inner walls).
        result["holes_found"] = len(hole_centers)
        
        # Check alignment with Original Bracket (if present)
        if original_bracket:
            # We can't easily hardcode coordinates because the part might move.
            # But we can check if the gasket holes overlap/align with bracket holes.
            pass

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Run the analysis script using FreeCAD command line
# We use 'freecadcmd' or 'freecad -c'
ANALYSIS_OUTPUT="/tmp/gasket_analysis.json"

if command -v freecadcmd > /dev/null 2>&1; then
    CMD="freecadcmd"
else
    CMD="freecad --console"
fi

# Run headless, suppress stdout noise, verify python execution
echo "Running geometry analysis..."
su - ga -c "DISPLAY=:1 $CMD $ANALYSIS_SCRIPT" > "$ANALYSIS_OUTPUT" 2>&1 || true

# Filter the output to find the JSON line (FreeCAD prints startup banner)
# We look for the line starting with "{" and ending with "}"
CLEAN_JSON=$(grep -o "{.*}" "$ANALYSIS_OUTPUT" | tail -1)
if [ -z "$CLEAN_JSON" ]; then
    CLEAN_JSON='{"error": "Failed to parse FreeCAD output"}'
fi

echo "$CLEAN_JSON" > /tmp/clean_analysis.json

# 4. Construct Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "geometry_analysis": $CLEAN_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to public location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json