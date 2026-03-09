#!/bin/bash
echo "=== Exporting create_staircase_array results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/FreeCAD/staircase.FCStd"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if file exists and gather basic stats
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Run internal geometry analysis using FreeCAD's Python API
# We create a script, run it with freecadcmd, and capture JSON output
ANALYSIS_SCRIPT="/tmp/analyze_staircase.py"
ANALYSIS_RESULT="/tmp/geometry_analysis.json"

cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import FreeCAD
import json
import sys
import os

output = {
    "valid_file": False,
    "volume_mm3": 0.0,
    "bbox_mm": [0.0, 0.0, 0.0],
    "object_count": 0,
    "max_object_name": ""
}

try:
    file_path = "/home/ga/Documents/FreeCAD/staircase.FCStd"
    if os.path.exists(file_path):
        # Open document in headless mode
        doc = FreeCAD.openDocument(file_path)
        output["valid_file"] = True
        output["object_count"] = len(doc.Objects)
        
        # Find the single largest solid (the staircase)
        max_vol = 0.0
        best_obj = None
        
        for obj in doc.Objects:
            # Check if object has a Shape
            if hasattr(obj, "Shape") and obj.Shape is not None:
                try:
                    vol = obj.Shape.Volume
                    # We look for something substantial, not just a datum plane
                    if vol > 1000: 
                        if vol > max_vol:
                            max_vol = vol
                            best_obj = obj
                except:
                    pass
        
        output["volume_mm3"] = max_vol
        if best_obj:
            output["max_object_name"] = best_obj.Name
            bb = best_obj.Shape.BoundBox
            output["bbox_mm"] = [bb.XLength, bb.YLength, bb.ZLength]
            
except Exception as e:
    output["error"] = str(e)

print(json.dumps(output))
PYEOF

# Run analysis inside container
if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Running geometry analysis..."
    # Use 'xvfb-run' if needed, or just standard display since we are headless
    # Note: freecadcmd is strictly command line, shouldn't need X, but sometimes modules require it
    su - ga -c "freecadcmd $ANALYSIS_SCRIPT" > "$ANALYSIS_RESULT" 2>/dev/null || true
    
    # If the file is empty or invalid JSON, write a default error
    if [ ! -s "$ANALYSIS_RESULT" ] || ! jq . "$ANALYSIS_RESULT" >/dev/null 2>&1; then
        echo '{"valid_file": false, "error": "Analysis script failed"}' > "$ANALYSIS_RESULT"
    fi
else
    echo '{"valid_file": false, "error": "File not found"}' > "$ANALYSIS_RESULT"
fi

# 4. Compile full result JSON
FINAL_JSON="/tmp/task_result.json"
# Read geometry analysis
GEO_JSON=$(cat "$ANALYSIS_RESULT")

# Create final structure using python to avoid jq dependency issues if missing
python3 -c "
import json
import os

try:
    geo = json.loads('''$GEO_JSON''')
except:
    geo = {}

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'output_exists': $OUTPUT_EXISTS, # boolean literal from shell var replacement? No, let's fix
    'file_created_during_task': $FILE_CREATED_DURING_TASK,
    'output_size_bytes': $OUTPUT_SIZE,
    'geometry': geo,
    'screenshot_path': '/tmp/task_final.png'
}
# Boolean fix for python
result['output_exists'] = True if '$OUTPUT_EXISTS' == 'true' else False
result['file_created_during_task'] = True if '$FILE_CREATED_DURING_TASK' == 'true' else False

print(json.dumps(result, indent=2))
" > "$FINAL_JSON"

# Handle permissions
chmod 666 "$FINAL_JSON"
chmod 666 /tmp/task_final.png 2>/dev/null || true

echo "Result exported to $FINAL_JSON"
cat "$FINAL_JSON"
echo "=== Export complete ==="