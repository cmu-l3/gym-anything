#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

OUTPUT_PATH="/home/ga/Documents/SolveSpace/base_enlarged.slvs"

# Check basic file existence and timestamps
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
else
    OUTPUT_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
fi

# Parse the .slvs file using Python to verify parameters and solver execution
# SolveSpace caches solved geometry coordinates in Entity.actPoint.x and .y
# If the solver actually ran, these coordinates will expand to fit the new 150x120 dimensions
cat > /tmp/parse_slvs.py << 'EOF'
import json, os, re

res = {
    "file_exists": False,
    "has_150_width": False,
    "has_120_height": False,
    "max_act_x": 0.0,
    "max_act_y": 0.0,
    "error": None
}

path = "/home/ga/Documents/SolveSpace/base_enlarged.slvs"
if os.path.exists(path):
    res["file_exists"] = True
    try:
        with open(path, "r") as f:
            content = f.read()
            
        # Parse parameters
        params = [float(x) for x in re.findall(r'Param\.val=([-\d\.]+)', content)]
        res["has_150_width"] = any(abs(p - 150.0) < 0.1 for p in params)
        res["has_120_height"] = any(abs(p - 120.0) < 0.1 for p in params)
        
        # Parse cached geometry solver outputs (absolute positions)
        act_x = [abs(float(x)) for x in re.findall(r'actPoint\.x=([-\d\.]+)', content)]
        act_y = [abs(float(y)) for y in re.findall(r'actPoint\.y=([-\d\.]+)', content)]
        
        res["max_act_x"] = max(act_x) if act_x else 0.0
        res["max_act_y"] = max(act_y) if act_y else 0.0
        
    except Exception as e:
        res["error"] = str(e)

with open("/tmp/parsed_slvs.json", "w") as f:
    json.dump(res, f)
EOF

python3 /tmp/parse_slvs.py

# Read the parsed JSON and merge it into our final result
PARSED_JSON=$(cat /tmp/parsed_slvs.json 2>/dev/null || echo "{}")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "slvs_data": $PARSED_JSON
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="