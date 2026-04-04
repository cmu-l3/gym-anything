#!/bin/bash
echo "=== Exporting model_clevis_rod_end results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define paths
OUTPUT_FILE="/home/ga/Documents/FreeCAD/clevis_rod_end.FCStd"
ANALYSIS_SCRIPT="/tmp/analyze_clevis.py"
ANALYSIS_RESULT="/tmp/geometry_analysis.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check if output exists
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    # Check if created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi

    # Create Python script to analyze geometry inside the container
    # We do this here because the host verifier might not have FreeCAD installed
    cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import FreeCAD
import Part
import json
import sys
import os

def analyze_model(file_path):
    result = {
        "valid_file": False,
        "solid_count": 0,
        "volume": 0.0,
        "bbox": None,
        "has_hole_feature": False,
        "has_slot_feature": False,
        "error": None
    }
    
    try:
        # Open document
        doc = FreeCAD.openDocument(file_path)
        result["valid_file"] = True
        
        # Find solids
        solids = []
        for obj in doc.Objects:
            if hasattr(obj, "Shape") and obj.Shape.ShapeType == "Solid":
                solids.append(obj.Shape)
            elif hasattr(obj, "Shape") and hasattr(obj.Shape, "Solids"):
                 solids.extend(obj.Shape.Solids)
        
        result["solid_count"] = len(solids)
        
        if solids:
            # Analyze the largest solid (assuming it's the main part)
            main_solid = max(solids, key=lambda s: s.Volume)
            result["volume"] = main_solid.Volume
            
            bb = main_solid.BoundBox
            result["bbox"] = {
                "xmin": bb.XMin, "xmax": bb.XMax,
                "ymin": bb.YMin, "ymax": bb.YMax,
                "zmin": bb.ZMin, "zmax": bb.ZMax,
                "x_len": bb.XLength,
                "y_len": bb.YLength,
                "z_len": bb.ZLength
            }
            
            # Check for hole feature (cylindrical faces with radius ~5mm)
            for face in main_solid.Faces:
                surf = face.Surface
                if hasattr(surf, "Radius"):
                    # 5mm radius = 10mm diameter
                    if 4.9 < surf.Radius < 5.1:
                        # Check orientation (Axis parallel to Y)
                        # The cylinder axis direction is surf.Axis
                        if abs(surf.Axis.y) > 0.9: 
                            result["has_hole_feature"] = True
            
            # Check for slot feature
            # We expect a gap of 12mm centered on Y.
            # So faces at Y approx +6 and -6, with normals pointing inward/outward Y
            slot_faces_found = 0
            for face in main_solid.Faces:
                # Check center of mass of face
                cm = face.CenterOfMass
                # If face is roughly planar and at Y = +/- 6
                if hasattr(face.Surface, "Normal"):
                    # Approximate check
                    if 5.5 < abs(cm.y) < 6.5:
                         slot_faces_found += 1
            
            if slot_faces_found >= 2:
                result["has_slot_feature"] = True

    except Exception as e:
        result["error"] = str(e)
        
    return result

if __name__ == "__main__":
    try:
        data = analyze_model(sys.argv[1])
        with open("/tmp/geometry_analysis.json", "w") as f:
            json.dump(data, f)
    except Exception as e:
        print(f"Analysis failed: {e}")
        # Write basic failure JSON
        with open("/tmp/geometry_analysis.json", "w") as f:
            json.dump({"error": str(e)}, f)
PYEOF

    # Run analysis using FreeCAD command line (headless)
    # We use 'freecadcmd' which is the console version
    # Note: freecadcmd might need environment variables set
    echo "Running geometry analysis..."
    FREECAD_LIB="/usr/lib/freecad/lib" # Adjust based on install
    export PYTHONPATH="$PYTHONPATH:$FREECAD_LIB"
    
    # Try running via the freecad binary in console mode if freecadcmd is tricky
    # Or just python3 if the modules are in path (often they are not default)
    
    # Robust method: use the installed freecadcmd
    if which freecadcmd > /dev/null; then
        freecadcmd "$ANALYSIS_SCRIPT" "$OUTPUT_FILE" > /tmp/analysis.log 2>&1
    else
        # Fallback: execute via python if freecad libs are in path
        python3 "$ANALYSIS_SCRIPT" "$OUTPUT_FILE" > /tmp/analysis.log 2>&1 || true
    fi

else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
    echo "{}" > "$ANALYSIS_RESULT"
fi

# Load analysis result content
if [ -f "$ANALYSIS_RESULT" ]; then
    ANALYSIS_CONTENT=$(cat "$ANALYSIS_RESULT")
else
    ANALYSIS_CONTENT="{}"
fi

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "geometry_analysis": $ANALYSIS_CONTENT
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json