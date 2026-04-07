#!/bin/bash
echo "=== Exporting find_replace_srs_text result ==="

source /workspace/scripts/task_utils.sh

# 1. Timestamp and Screenshot
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
take_screenshot /tmp/task_final.png

# 2. Paths
PROJECT_PATH="/home/ga/Documents/ReqView/find_replace_project"
SRS_JSON="$PROJECT_PATH/documents/SRS.json"

# 3. Check File Modification
FILE_MODIFIED="false"
SRS_MTIME=0
if [ -f "$SRS_JSON" ]; then
    SRS_MTIME=$(stat -c %Y "$SRS_JSON" 2>/dev/null || echo "0")
    if [ "$SRS_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 4. Capture Final Stats
# We parse the JSON again to see final counts
python3 << PYEOF
import json
import os

srs_path = "$SRS_JSON"
result = {
    "final_sensor_count": -1,
    "final_detector_count": -1,
    "error": None
}

if os.path.exists(srs_path):
    try:
        with open(srs_path, 'r') as f:
            data = json.load(f)
        
        def count_terms(items):
            s_count = 0
            d_count = 0
            for item in items:
                text = (item.get('text', '') or item.get('description', '')).lower()
                s_count += text.count("sensor")
                d_count += text.count("detector")
                if 'children' in item:
                    sc, dc = count_terms(item['children'])
                    s_count += sc
                    d_count += dc
            return s_count, d_count

        result["final_sensor_count"], result["final_detector_count"] = count_terms(data.get('data', []))
    except Exception as e:
        result["error"] = str(e)

with open("/tmp/final_stats.json", "w") as f:
    json.dump(result, f)
PYEOF

# 5. Compile Result JSON
# We combine everything into one file for the verifier
# We also copy the SRS file to /tmp for easy extraction by copy_from_env
cp "$SRS_JSON" /tmp/final_srs.json 2>/dev/null || true

python3 << PYEOF
import json
import os

try:
    with open("/tmp/initial_state.json", "r") as f:
        initial = json.load(f)
except:
    initial = {}

try:
    with open("/tmp/final_stats.json", "r") as f:
        final = json.load(f)
except:
    final = {}

task_result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_modified": "$FILE_MODIFIED" == "true",
    "srs_mtime": $SRS_MTIME,
    "initial": initial,
    "final": final,
    "srs_path": "/tmp/final_srs.json",
    "screenshot_path": "/tmp/task_final.png"
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(task_result, f, indent=2)
PYEOF

# Cleanup permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/final_srs.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="