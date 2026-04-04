#!/bin/bash
echo "=== Exporting model_naca_airfoil result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/FreeCAD/wing_section.FCStd"
ANALYSIS_JSON="/tmp/geometry_analysis.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check if app is running
APP_RUNNING=$(pgrep -f "FreeCAD" > /dev/null && echo "true" || echo "false")

# ==============================================================================
# Headless Geometry Analysis
# We use FreeCAD's internal Python to verify geometry without relying on the GUI
# ==============================================================================

if [ -f "$OUTPUT_PATH" ]; then
    echo "Analyzing geometry using FreeCAD Python API..."
    
    cat << 'PY_EOF' > /tmp/analyze_wing.py
import FreeCAD
import json
import sys
import math

result = {
    "valid_file": False,
    "has_solid": False,
    "bbox_x": 0,
    "bbox_y": 0,
    "bbox_z": 0,
    "volume": 0,
    "surface_area": 0,
    "error": ""
}

try:
    doc = FreeCAD.openDocument("/home/ga/Documents/FreeCAD/wing_section.FCStd")
    result["valid_file"] = True
    
    # Find the main solid
    # We look for the object with the largest volume
    max_vol = 0
    best_obj = None
    
    for obj in doc.Objects:
        if hasattr(obj, 'Shape') and obj.Shape.Volume > 100: # Filter out construction geometry
            if obj.Shape.Volume > max_vol:
                max_vol = obj.Shape.Volume
                best_obj = obj
    
    if best_obj:
        shape = best_obj.Shape
        result["has_solid"] = (shape.ShapeType == "Solid" or shape.ShapeType == "CompSolid" or len(shape.Solids) > 0)
        result["volume"] = shape.Volume
        result["surface_area"] = shape.Area
        
        # Bounding Box
        bb = shape.BoundBox
        result["bbox_x"] = bb.XLength
        result["bbox_y"] = bb.YLength
        result["bbox_z"] = bb.ZLength
        
except Exception as e:
    result["error"] = str(e)

with open("/tmp/geometry_analysis.json", "w") as f:
    json.dump(result, f)
PY_EOF

    # Run analysis script using freecadcmd (headless)
    # We must use the 'ga' user environment to access the file correctly
    su - ga -c "freecadcmd /tmp/analyze_wing.py" > /dev/null 2>&1 || true
else
    echo "Output file not found."
    echo '{"valid_file": false, "error": "File not found"}' > "$ANALYSIS_JSON"
fi

# ==============================================================================
# Gather Metrics
# ==============================================================================

# Read analysis result
if [ -f "$ANALYSIS_JSON" ]; then
    cat "$ANALYSIS_JSON"
else
    echo "{}"
fi > /tmp/raw_analysis.json

# File timestamp check
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE=0
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Create final result JSON
python3 -c "
import json
import os

try:
    with open('/tmp/raw_analysis.json', 'r') as f:
        analysis = json.load(f)
except:
    analysis = {}

result = {
    'task_start': $TASK_START,
    'output_exists': os.path.exists('$OUTPUT_PATH'),
    'file_created_during_task': $FILE_CREATED_DURING_TASK,
    'output_size_bytes': $OUTPUT_SIZE,
    'app_was_running': $APP_RUNNING,
    'screenshot_path': '/tmp/task_final.png',
    'geometry': analysis
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="