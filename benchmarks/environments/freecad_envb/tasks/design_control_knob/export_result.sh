#!/bin/bash
echo "=== Exporting design_control_knob results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Target file
FILE_PATH="/home/ga/Documents/FreeCAD/control_knob.FCStd"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check if file exists
if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$FILE_PATH")
    FILE_MTIME=$(stat -c%Y "$FILE_PATH")
    
    # Check if created during task
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# ------------------------------------------------------------------
# Run Headless Analysis inside the container
# ------------------------------------------------------------------
ANALYSIS_JSON="/tmp/model_analysis.json"
echo "{}" > "$ANALYSIS_JSON"

if [ "$FILE_EXISTS" = "true" ]; then
    echo "Running FreeCAD geometric analysis..."
    
    # Create python script for analysis
    cat > /tmp/analyze_knob.py << 'PYEOF'
import FreeCAD
import json
import sys
import os

result = {
    "valid_solid": False,
    "volume": 0.0,
    "bbox": [0,0,0],
    "com": [0,0,0],
    "features": [],
    "error": None
}

try:
    doc_path = "/home/ga/Documents/FreeCAD/control_knob.FCStd"
    if not os.path.exists(doc_path):
        raise Exception("File not found")
        
    doc = FreeCAD.openDocument(doc_path)
    
    # Find the main solid
    # We look for the body with the largest volume
    best_obj = None
    max_vol = 0
    
    features_found = []
    
    for obj in doc.Objects:
        # Collect feature types
        type_str = obj.TypeId
        # Simplified feature check
        if "Pad" in type_str or "Pad" in obj.Name: features_found.append("Pad")
        if "Pocket" in type_str or "Pocket" in obj.Name: features_found.append("Pocket")
        if "Fillet" in type_str or "Fillet" in obj.Name: features_found.append("Fillet")
        
        if hasattr(obj, "Shape") and obj.Shape.Volume > 100:
            if obj.Shape.Volume > max_vol:
                max_vol = obj.Shape.Volume
                best_obj = obj

    result["features"] = list(set(features_found))

    if best_obj:
        shape = best_obj.Shape
        result["valid_solid"] = shape.isValid()
        result["volume"] = shape.Volume
        bbox = shape.BoundBox
        result["bbox"] = [bbox.XLength, bbox.YLength, bbox.ZLength]
        com = shape.CenterOfMass
        result["com"] = [com.x, com.y, com.z]
    else:
        result["error"] = "No solid object found in document"

except Exception as e:
    result["error"] = str(e)

with open("/tmp/model_analysis.json", "w") as f:
    json.dump(result, f)
PYEOF

    # Run analysis with freecadcmd
    # We mask stdout/stderr to keep export clean, relies on json file output
    su - ga -c "freecadcmd /tmp/analyze_knob.py" > /tmp/freecad_analysis.log 2>&1 || true
    
    # Debug: print analysis log if empty json
    if [ ! -s "$ANALYSIS_JSON" ] || [ "$(cat $ANALYSIS_JSON)" == "{}" ]; then
        echo "WARNING: Analysis failed. Log:"
        head -n 20 /tmp/freecad_analysis.log
    fi
fi

# ------------------------------------------------------------------
# Combine results
# ------------------------------------------------------------------
FINAL_JSON="/tmp/task_result.json"
cat > "$FINAL_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png",
    "analysis": $(cat "$ANALYSIS_JSON" 2>/dev/null || echo "null")
}
EOF

# Ensure permissions
chmod 666 "$FINAL_JSON"
echo "Result exported to $FINAL_JSON"
cat "$FINAL_JSON"
echo "=== Export complete ==="