#!/bin/bash
echo "=== Exporting design_radial_impeller results ==="

source /workspace/scripts/task_utils.sh

# Capture final visual state
take_screenshot /tmp/task_final.png

OUTPUT_FILE="/home/ga/Documents/FreeCAD/radial_impeller.FCStd"
REPORT_FILE="/tmp/geometry_report.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check if output file exists
if [ -f "$OUTPUT_FILE" ]; then
    echo "Output file found."
    
    # Create a Python script to inspect the geometry INSIDE the environment
    # This is critical because the host verifier doesn't have FreeCAD libs
    cat > /tmp/inspect_geometry.py << 'PYEOF'
import FreeCAD
import json
import sys
import os

file_path = "/home/ga/Documents/FreeCAD/radial_impeller.FCStd"
result = {
    "file_exists": True,
    "valid_document": False,
    "volume": 0.0,
    "bbox": [0,0,0],
    "center_of_mass": [0,0,0],
    "features": [],
    "polar_pattern_count": 0,
    "has_solid": False
}

try:
    if not os.path.exists(file_path):
        result["file_exists"] = False
    else:
        doc = FreeCAD.openDocument(file_path)
        result["valid_document"] = True
        
        # Analyze objects
        for obj in doc.Objects:
            # Store feature types found
            type_name = obj.TypeId
            name = obj.Name
            result["features"].append({"name": name, "type": type_name})
            
            # Check for PolarPattern specifically
            if "PolarPattern" in type_name or "PolarPattern" in name:
                # Try to get occurrence count
                if hasattr(obj, "Occurrences"):
                    result["polar_pattern_count"] = obj.Occurrences
                elif hasattr(obj, "Number"): # Some versions use 'Number'
                     result["polar_pattern_count"] = obj.Number

            # Analyze the final solid shape (usually the Tip of the Body)
            # We look for a Body object and check its Shape
            if obj.TypeId == "PartDesign::Body":
                if hasattr(obj, "Shape") and obj.Shape.Volume > 0:
                    result["has_solid"] = True
                    result["volume"] = obj.Shape.Volume
                    bbox = obj.Shape.BoundBox
                    result["bbox"] = [bbox.XLength, bbox.YLength, bbox.ZLength]
                    com = obj.Shape.CenterOfMass
                    result["center_of_mass"] = [com.x, com.y, com.z]
            
            # Fallback: if no Body found or analyzed, check for any solid with significant volume
            if not result["has_solid"] and hasattr(obj, "Shape"):
                 if obj.Shape.ShapeType == "Solid" and obj.Shape.Volume > 1000:
                    result["has_solid"] = True
                    result["volume"] = obj.Shape.Volume
                    bbox = obj.Shape.BoundBox
                    result["bbox"] = [bbox.XLength, bbox.YLength, bbox.ZLength]
                    com = obj.Shape.CenterOfMass
                    result["center_of_mass"] = [com.x, com.y, com.z]

except Exception as e:
    result["error"] = str(e)

with open("/tmp/geometry_report.json", "w") as f:
    json.dump(result, f)
PYEOF

    # Run inspection script using FreeCAD's python executable
    # We use freecadcmd (headless) for this
    echo "Running geometry inspection..."
    timeout 20s freecadcmd /tmp/inspect_geometry.py > /tmp/inspection.log 2>&1 || echo "Inspection timed out or failed"

else
    echo "Output file NOT found."
    echo '{"file_exists": false}' > "$REPORT_FILE"
fi

# Prepare result JSON for the host verifier
# We wrap the inspection report and add environment-level metadata (timestamps, etc.)
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Read geometry report content safely
GEOMETRY_DATA="{}"
if [ -f "$REPORT_FILE" ]; then
    GEOMETRY_DATA=$(cat "$REPORT_FILE")
fi

# Create final combined JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "geometry_analysis": $GEOMETRY_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json
chmod 666 /tmp/task_final.png 2>/dev/null || true

echo "=== Export complete ==="