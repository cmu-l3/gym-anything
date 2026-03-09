#!/bin/bash
echo "=== Exporting design_fitted_box_lid results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/FreeCAD/project_box_assembly.FCStd"
ANALYSIS_JSON="/tmp/geometry_analysis.json"

# Capture final visual state
take_screenshot /tmp/task_final.png

# Check if output file exists
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi

    # ---------------------------------------------------------
    # Analyze Geometry using FreeCAD Python API (Headless)
    # ---------------------------------------------------------
    echo "Running geometry analysis..."
    
    # Create analysis script
    cat > /tmp/analyze_box.py << 'PYEOF'
import FreeCAD
import Part
import json
import sys
import os

filepath = "/home/ga/Documents/FreeCAD/project_box_assembly.FCStd"
result = {
    "bodies_found": 0,
    "bodies": [],
    "error": None
}

try:
    if not os.path.exists(filepath):
        raise FileNotFoundError("File not found")

    doc = FreeCAD.open(filepath)
    
    # Find all Part Design Bodies
    # We look for objects with TypeId 'PartDesign::Body'
    # Or simple Part objects if the agent used Part workbench (though task asks for Part Design)
    
    bodies = []
    
    # Helper to get bounding box dims sorted
    def get_dims(shape):
        bb = shape.BoundBox
        dims = sorted([bb.XLength, bb.YLength, bb.ZLength])
        return dims

    for obj in doc.Objects:
        if obj.TypeId == 'PartDesign::Body':
            if obj.Shape.Volume > 10: # Filter out empty/default bodies
                bodies.append({
                    "name": obj.Name,
                    "label": obj.Label,
                    "volume": obj.Shape.Volume,
                    "dims": get_dims(obj.Shape),
                    "type": "PartDesign::Body"
                })
        # Fallback: Check for loose solids if they aren't in a Body (Partial credit scenario)
        elif obj.TypeId == 'Part::Feature' and obj.Shape.Solid:
             # Check if this solid is part of a Body (don't double count)
             is_child = False
             for parent in doc.Objects:
                 if parent.TypeId == 'PartDesign::Body' and obj in parent.Group:
                     is_child = True
             if not is_child and obj.Shape.Volume > 10:
                 bodies.append({
                    "name": obj.Name,
                    "label": obj.Label,
                    "volume": obj.Shape.Volume,
                    "dims": get_dims(obj.Shape),
                    "type": "Part::Feature"
                 })

    result["bodies_found"] = len(bodies)
    result["bodies"] = bodies

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

    # Run the analysis script using freecadcmd (headless)
    # Using 'su - ga' to ensure permissions match
    su - ga -c "freecadcmd /tmp/analyze_box.py" > "$ANALYSIS_JSON" 2>/dev/null || true
    
    # Sanitize output (sometimes freecadcmd prints version info before json)
    # We extract the last line which should be the JSON
    tail -n 1 "$ANALYSIS_JSON" > "${ANALYSIS_JSON}.clean"
    mv "${ANALYSIS_JSON}.clean" "$ANALYSIS_JSON"

else
    OUTPUT_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
    OUTPUT_SIZE="0"
    echo "{}" > "$ANALYSIS_JSON"
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "FreeCAD" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
# Embed the analysis json directly
ANALYSIS_CONTENT=$(cat "$ANALYSIS_JSON")
if [ -z "$ANALYSIS_CONTENT" ]; then ANALYSIS_CONTENT="{}"; fi

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "geometry_analysis": $ANALYSIS_CONTENT
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="