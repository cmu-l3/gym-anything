#!/bin/bash
echo "=== Exporting create_pipe_elbow results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/FreeCAD/pipe_elbow.FCStd"

# 1. basic file checks
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
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

# 2. Geometric Analysis using FreeCAD's internal Python
# We create a temporary python script to analyze the shape inside the container
GEOMETRY_JSON="{}"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Running geometric analysis..."
    
    ANALYSIS_SCRIPT="/tmp/analyze_elbow.py"
    cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import FreeCAD
import sys
import json

result = {
    "valid_shape": False,
    "volume": 0.0,
    "bbox": [0.0, 0.0, 0.0],
    "faces": 0,
    "error": ""
}

try:
    # Open the document
    doc = FreeCAD.openDocument('/home/ga/Documents/FreeCAD/pipe_elbow.FCStd')
    
    # Find the best candidate object (largest volume solid)
    best_obj = None
    max_vol = 0.0
    
    for obj in doc.Objects:
        if hasattr(obj, 'Shape') and obj.Shape.isValid():
            # Check if it has volume (some helper objects might not)
            try:
                vol = obj.Shape.Volume
                # Filter out tiny artifacts, look for substantial geometry
                if vol > max_vol:
                    max_vol = vol
                    best_obj = obj
            except:
                continue
                
    if best_obj:
        result["valid_shape"] = True
        result["volume"] = max_vol
        bb = best_obj.Shape.BoundBox
        # Sort bbox dimensions to allow orientation independence
        # Target is roughly [25, 52.5, 52.5]
        dims = sorted([bb.XLength, bb.YLength, bb.ZLength])
        result["bbox"] = dims
        result["faces"] = len(best_obj.Shape.Faces)
    else:
        result["error"] = "No valid solid object found in document"

except Exception as e:
    result["error"] = str(e)

print("JSON_START")
print(json.dumps(result))
print("JSON_END")
PYEOF

    # Run the script using freecadcmd (headless)
    # We use a wrapper to handle the environment variables usually set by the GUI
    ANALYSIS_OUTPUT=$(su - ga -c "freecadcmd $ANALYSIS_SCRIPT" 2>&1 || true)
    
    # Extract JSON from output
    GEOMETRY_JSON=$(echo "$ANALYSIS_OUTPUT" | sed -n '/JSON_START/,/JSON_END/p' | grep -v "JSON_" || echo "{}")
    
    # Fallback if extraction failed
    if [ -z "$GEOMETRY_JSON" ] || [ "$GEOMETRY_JSON" == "{}" ]; then
        GEOMETRY_JSON="{\"error\": \"Failed to parse analysis output\", \"raw_output\": \"$(echo $ANALYSIS_OUTPUT | head -c 200)\"}"
    fi
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Check if app is running
APP_RUNNING=$(pgrep -f "freecad" > /dev/null && echo "true" || echo "false")

# 5. Create Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "geometry_analysis": $GEOMETRY_JSON
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="