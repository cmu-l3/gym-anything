#!/bin/bash
set -e
echo "=== Exporting design_architectural_frame results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/FreeCAD/structural_frame.FCStd"
ANALYSIS_JSON="/tmp/structural_analysis.json"

# Check if output file exists
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    
    echo "File found. extracting geometry data..."
    
    # Create a Python script to extract object data using FreeCAD's internal python
    cat > /tmp/extract_structure.py << 'PYEOF'
import FreeCAD
import json
import sys

output_file = "/tmp/structural_analysis.json"
doc_path = "/home/ga/Documents/FreeCAD/structural_frame.FCStd"

data = {
    "objects": [],
    "axes": [],
    "error": None
}

try:
    doc = FreeCAD.open(doc_path)
    
    for obj in doc.Objects:
        obj_data = {
            "name": obj.Name,
            "type": obj.TypeId,
            "label": obj.Label,
            "role": getattr(obj, "Role", "Unknown"),
            "placement": {
                "x": obj.Placement.Base.x,
                "y": obj.Placement.Base.y,
                "z": obj.Placement.Base.z
            },
            "bbox": {}
        }
        
        # Get bounding box if shape exists
        if hasattr(obj, "Shape") and not obj.Shape.isNull():
            bb = obj.Shape.BoundBox
            obj_data["bbox"] = {
                "x_len": bb.XLength,
                "y_len": bb.YLength,
                "z_len": bb.ZLength,
                "x_min": bb.XMin,
                "y_min": bb.YMin,
                "z_min": bb.ZMin,
                "z_max": bb.ZMax
            }
            
        data["objects"].append(obj_data)
        
        # Special check for Axis/Grid
        if "Arch::Axis" in obj.TypeId or "Axis" in obj.Name:
            data["axes"].append(obj_data)

except Exception as e:
    data["error"] = str(e)
    print(f"Error extracting data: {e}")

with open(output_file, "w") as f:
    json.dump(data, f, indent=2)
PYEOF

    # Run the extraction script using FreeCAD command line
    # We use a separate shell to avoid environment pollution
    su - ga -c "freecadcmd /tmp/extract_structure.py" > /tmp/extraction.log 2>&1 || true
    
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    echo "{}" > "$ANALYSIS_JSON"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "analysis_json_path": "$ANALYSIS_JSON"
}
EOF

# Move result to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Copy analysis file to be readable
if [ -f "$ANALYSIS_JSON" ]; then
    chmod 666 "$ANALYSIS_JSON"
fi

echo "=== Export complete ==="