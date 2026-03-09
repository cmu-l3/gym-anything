#!/bin/bash
echo "=== Exporting measure_part_geometry results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Documents/FreeCAD/measurement_report.txt"
MODEL_PATH="/home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if report file exists and check timestamp
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_SIZE="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# 3. GENERATE GROUND TRUTH
# We run a python script inside the container using FreeCAD's cmdline to get the ACTUAL values.
# This ensures verification is robust even if the model version changes slightly.
echo "Generating ground truth..."
cat > /tmp/generate_gt.py << PYEOF
import FreeCAD
import sys
import json

try:
    # Open the document
    doc = FreeCAD.open("$MODEL_PATH")
    
    # Find the main solid (heuristic: largest volume object)
    best_shape = None
    best_vol = -1.0
    
    for obj in doc.Objects:
        if hasattr(obj, 'Shape') and hasattr(obj.Shape, 'Volume'):
            try:
                v = obj.Shape.Volume
                # Filter out tiny artifacts, look for significant solids
                if v > best_vol:
                    best_vol = v
                    best_shape = obj.Shape
            except:
                continue
                
    if best_shape:
        bbox = best_shape.BoundBox
        com = best_shape.CenterOfMass
        
        data = {
            "BoundingBox_X": bbox.XLength,
            "BoundingBox_Y": bbox.YLength,
            "BoundingBox_Z": bbox.ZLength,
            "Volume": best_shape.Volume,
            "SurfaceArea": best_shape.Area,
            "CenterOfMass_X": com.x,
            "CenterOfMass_Y": com.y,
            "CenterOfMass_Z": com.z,
            "success": True
        }
    else:
        data = {"success": False, "error": "No solid found"}
        
except Exception as e:
    data = {"success": False, "error": str(e)}

with open("/tmp/ground_truth.json", "w") as f:
    json.dump(data, f)
PYEOF

# Execute the ground truth script using freecadcmd
# We use 'timeout' to prevent hanging
timeout 30s freecadcmd /tmp/generate_gt.py > /dev/null 2>&1 || true

# 4. Prepare Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_size_bytes": $REPORT_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "report_file_path": "$REPORT_PATH",
    "ground_truth_path": "/tmp/ground_truth.json"
}
EOF

# Move to standard output location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="