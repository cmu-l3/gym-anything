#!/bin/bash
echo "=== Exporting extract_mass_properties result ==="

# Define paths
DOCS_DIR="/home/ga/Documents/FreeCAD"
MODEL_FILE="$DOCS_DIR/T8_housing_bracket.FCStd"
REPORT_FILE="$DOCS_DIR/mass_report.json"
GROUND_TRUTH_FILE="/tmp/ground_truth.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Calculate Ground Truth using FreeCAD Python API (headless)
# We do this here so the verifier (on host) gets the absolute truth from the specific FreeCAD version/file used.
echo "Calculating ground truth..."
cat > /tmp/calc_truth.py << EOF
import FreeCAD
import json
import sys

try:
    doc = FreeCAD.openDocument("$MODEL_FILE")
    
    # Find the main solid. Usually the T8 bracket is a single solid or PartDesign Body.
    # We iterate to find the object with the largest volume.
    best_obj = None
    max_vol = 0.0
    
    for obj in doc.Objects:
        if hasattr(obj, 'Shape') and not obj.Shape.isNull():
            if obj.Shape.Volume > max_vol:
                max_vol = obj.Shape.Volume
                best_obj = obj
                
    if best_obj:
        s = best_obj.Shape
        bbox = s.BoundBox
        com = s.CenterOfMass
        
        data = {
            "volume_mm3": s.Volume,
            "surface_area_mm2": s.Area,
            "bounding_box_x_mm": bbox.XLength,
            "bounding_box_y_mm": bbox.YLength,
            "bounding_box_z_mm": bbox.ZLength,
            "center_of_mass_x_mm": com.x,
            "center_of_mass_y_mm": com.y,
            "center_of_mass_z_mm": com.z,
            "mass_grams": s.Volume * 0.0027  # Density 0.0027 g/mm^3
        }
        
        with open("$GROUND_TRUTH_FILE", "w") as f:
            json.dump(data, f)
        print("Ground truth calculated successfully.")
    else:
        print("No solid found in document.")
        
except Exception as e:
    print(f"Error calculating truth: {e}")
EOF

# Run the calculation script using freecadcmd
if [ -f "$MODEL_FILE" ]; then
    freecadcmd /tmp/calc_truth.py > /tmp/calc_log.txt 2>&1
else
    echo "Model file missing, cannot calc truth."
fi

# 2. Check Agent Output File
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT="{}"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Read content safely
    REPORT_CONTENT=$(cat "$REPORT_FILE")
fi

# 3. Read Ground Truth Content
GROUND_TRUTH_CONTENT="{}"
if [ -f "$GROUND_TRUTH_FILE" ]; then
    GROUND_TRUTH_CONTENT=$(cat "$GROUND_TRUTH_FILE")
fi

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content": $REPORT_CONTENT,
    "ground_truth": $GROUND_TRUTH_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="