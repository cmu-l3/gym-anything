#!/bin/bash
set -e
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Paths
OUTPUT_PATH="/home/ga/Documents/FreeCAD/tensile_specimen.FCStd"
ANALYSIS_SCRIPT="/tmp/analyze_geometry.py"
RESULT_JSON="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if file exists and was created during task
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Run geometric analysis using FreeCAD's internal Python
# We create a python script that FreeCAD will execute to analyze the geometry
cat > "$ANALYSIS_SCRIPT" << 'EOF'
import FreeCAD
import Part
import json
import sys
import os

result = {
    "valid_solid": False,
    "bbox_length": 0.0,
    "bbox_width": 0.0,
    "bbox_height": 0.0,
    "volume": 0.0,
    "waist_width": 0.0,
    "error": ""
}

try:
    file_path = "/home/ga/Documents/FreeCAD/tensile_specimen.FCStd"
    if not os.path.exists(file_path):
        result["error"] = "File not found"
    else:
        # Open document
        doc = FreeCAD.open(file_path)
        
        # Find the main solid object
        # We look for the first object that has a 'Shape' property and is a solid
        target_obj = None
        for obj in doc.Objects:
            if hasattr(obj, "Shape") and obj.Shape.Solid:
                target_obj = obj
                break
        
        if target_obj:
            shape = target_obj.Shape
            result["valid_solid"] = True
            
            # Bounding Box
            bbox = shape.BoundBox
            result["bbox_length"] = bbox.XLength
            result["bbox_width"] = bbox.YLength
            result["bbox_height"] = bbox.ZLength
            result["volume"] = shape.Volume
            
            # Measure Waist Width (Gauge Width)
            # We cut the shape with a thin slice at X=0 (center)
            # Create a box slice: small X (1mm), large Y and Z
            # Center it at (0,0,0) - assuming agent centered the part as requested
            # If not centered, this might fail, but centering is part of the "Symmetric" requirement.
            
            # Try to handle non-centered parts by using the bbox center
            center = bbox.Center
            
            # Create a slicing plane/box
            slice_box = Part.makeBox(1.0, 200.0, 200.0) # 1mm thick X-slice
            # Move box so its center is at the shape's center
            slice_box.translate(FreeCAD.Vector(center.x - 0.5, center.y - 100.0, center.z - 100.0))
            
            # Calculate intersection
            waist_slice = shape.common(slice_box)
            if waist_slice.Volume > 0:
                result["waist_width"] = waist_slice.BoundBox.YLength
            else:
                result["error"] = "Could not measure waist (part might be misaligned)"
                
        else:
            result["error"] = "No solid object found in document"

except Exception as e:
    result["error"] = str(e)

# Output result to JSON
with open("/tmp/analysis_result.json", "w") as f:
    json.dump(result, f)
EOF

# Execute the analysis script headless
if [ "$FILE_EXISTS" = "true" ]; then
    echo "Running geometry analysis..."
    # freecadcmd runs python script in console mode
    # We su to ga to have access to the file permissions
    su - ga -c "freecadcmd $ANALYSIS_SCRIPT" > /dev/null 2>&1 || echo "Analysis failed"
else
    # Create empty failure result
    echo '{"error": "File missing"}' > /tmp/analysis_result.json
fi

# 4. Construct Final JSON
# Merge file stats and geometry analysis
cat > /tmp/merge_results.py << EOF
import json
import time

try:
    with open('/tmp/analysis_result.json', 'r') as f:
        analysis = json.load(f)
except:
    analysis = {}

output = {
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "analysis": analysis,
    "screenshot_path": "/tmp/task_final.png"
}

with open('$RESULT_JSON', 'w') as f:
    json.dump(output, f, indent=2)
EOF

python3 /tmp/merge_results.py

# 5. Permission cleanup
chmod 666 "$RESULT_JSON"

echo "Result stored in $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="