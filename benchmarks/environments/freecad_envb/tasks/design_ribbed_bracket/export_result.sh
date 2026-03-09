#!/bin/bash
echo "=== Exporting design_ribbed_bracket results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/FreeCAD/ribbed_bracket.FCStd"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check file existence and timestamps
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
fi

# 3. Geometric Analysis using FreeCAD Python API (headless)
# We create a python script to run INSIDE the container to inspect the model geometry
cat > /tmp/analyze_geometry.py << 'PYEOF'
import FreeCAD
import sys
import json
import os

result = {
    "valid_doc": False,
    "has_rib": False,
    "volume": 0.0,
    "bbox": [0,0,0],
    "objects": []
}

try:
    doc_path = "/home/ga/Documents/FreeCAD/ribbed_bracket.FCStd"
    if os.path.exists(doc_path):
        doc = FreeCAD.openDocument(doc_path)
        result["valid_doc"] = True
        
        total_volume = 0.0
        bbox_max = [0, 0, 0]
        
        for obj in doc.Objects:
            # List object types for debugging
            result["objects"].append(obj.TypeId)
            
            # Check for Rib feature
            if "Rib" in obj.TypeId or (hasattr(obj, "Proxy") and "Rib" in str(obj.Proxy)):
                result["has_rib"] = True
            
            # Check solids for volume and bbox
            if hasattr(obj, "Shape") and obj.Shape.Volume > 1:
                # We assume the Body object contains the final solid
                if obj.TypeId == "PartDesign::Body":
                    total_volume = obj.Shape.Volume
                    bb = obj.Shape.BoundBox
                    bbox_max = [bb.XLength, bb.YLength, bb.ZLength]
                elif obj.TypeId == "Part::Feature" and total_volume == 0:
                     # Fallback if they didn't use PartDesign Body properly but made solids
                    total_volume += obj.Shape.Volume
                    bb = obj.Shape.BoundBox
                    bbox_max = [max(bbox_max[0], bb.XLength), max(bbox_max[1], bb.YLength), max(bbox_max[2], bb.ZLength)]

        result["volume"] = total_volume
        result["bbox"] = bbox_max
        
except Exception as e:
    result["error"] = str(e)

with open("/tmp/geometry_analysis.json", "w") as f:
    json.dump(result, f)
PYEOF

# Run the analysis script using freecadcmd (headless)
# We accept failure in case freecadcmd crashes, so we don't block export
echo "Running geometry analysis..."
if [ "$OUTPUT_EXISTS" = "true" ]; then
    timeout 20s freecadcmd /tmp/analyze_geometry.py > /tmp/analysis.log 2>&1 || true
else
    echo "{"valid_doc": false}" > /tmp/geometry_analysis.json
fi

# 4. Merge results into final JSON
# We use python to robustly merge the shell variables and the analysis JSON
python3 -c "
import json
import os

try:
    with open('/tmp/geometry_analysis.json', 'r') as f:
        analysis = json.load(f)
except:
    analysis = {}

final = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'output_exists': $OUTPUT_EXISTS,
    'file_created_during_task': $FILE_CREATED_DURING_TASK,
    'output_size_bytes': $OUTPUT_SIZE,
    'geometry': analysis
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(final, f)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete. Result:"
cat /tmp/task_result.json