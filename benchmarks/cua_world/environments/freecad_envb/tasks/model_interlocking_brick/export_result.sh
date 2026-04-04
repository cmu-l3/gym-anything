#!/bin/bash
echo "=== Exporting model_interlocking_brick results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/FreeCAD/brick_2x2.FCStd"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check file existence and timestamps
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Run Internal Geometry Analysis using FreeCADCmd (headless)
# We create a python script to analyze the model inside the container
cat > /tmp/analyze_brick.py << 'PYEOF'
import FreeCAD
import Part
import json
import sys
import os

output_path = "/home/ga/Documents/FreeCAD/brick_2x2.FCStd"
result = {
    "valid": False,
    "volume": 0.0,
    "bbox": [0.0, 0.0, 0.0],
    "faces": 0,
    "solid_count": 0,
    "error": None
}

try:
    if not os.path.exists(output_path):
        result["error"] = "File not found"
    else:
        doc = FreeCAD.openDocument(output_path)
        
        # Find the main result object
        # We look for the largest solid in the document
        max_vol = 0
        best_shape = None
        solid_count = 0
        
        for obj in doc.Objects:
            if hasattr(obj, 'Shape') and obj.Shape.isValid():
                if obj.Shape.ShapeType == 'Solid' or obj.Shape.ShapeType == 'Compound':
                    vol = obj.Shape.Volume
                    # Filter out tiny artifacts
                    if vol > 100: 
                        solid_count += 1
                        if vol > max_vol:
                            max_vol = vol
                            best_shape = obj.Shape

        result["solid_count"] = solid_count
        
        if best_shape:
            result["valid"] = best_shape.isValid()
            result["volume"] = best_shape.Volume
            bbox = best_shape.BoundBox
            # Sort dimensions for easier comparison (LxWxH)
            dims = sorted([bbox.XLength, bbox.YLength, bbox.ZLength])
            result["bbox"] = dims
            result["faces"] = len(best_shape.Faces)
        else:
            result["error"] = "No valid solid found in document"

except Exception as e:
    result["error"] = str(e)

with open("/tmp/brick_analysis.json", "w") as f:
    json.dump(result, f)
PYEOF

echo "Running geometry analysis..."
# Run the analysis script using FreeCAD's python executable or command line
# Note: freecadcmd might need env vars
export PYTHONPATH=$PYTHONPATH:/usr/lib/freecad/lib
timeout 30s freecadcmd /tmp/analyze_brick.py > /tmp/analysis_log.txt 2>&1 || echo "Analysis timed out or failed"

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "analysis_path": "/tmp/brick_analysis.json"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
chmod 666 /tmp/brick_analysis.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json