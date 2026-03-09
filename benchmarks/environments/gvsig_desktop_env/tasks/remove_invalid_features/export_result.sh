#!/bin/bash
echo "=== Exporting remove_invalid_features result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

TARGET_SHP="/home/ga/gvsig_data/projects/countries_cleaning.shp"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file modification
FILE_MODIFIED="false"
if [ -f "$TARGET_SHP" ]; then
    FILE_MTIME=$(stat -c %Y "$TARGET_SHP" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Analyze the result shapefile using Python
# We do this INSIDE the container to use installed pyshp and avoid host dependencies
echo "Analyzing shapefile content..."
python3 << EOF
import shapefile
import json
import os
import sys

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": False,
    "file_modified": False, # Bash check passed in via var if needed, but we check mtime here too
    "final_count": 0,
    "invalid_remaining": 0,
    "valid_remaining": 0,
    "error": None
}

target = "$TARGET_SHP"
task_start = $TASK_START

if os.path.exists(target):
    result["file_exists"] = True
    if os.path.getmtime(target) > task_start:
        result["file_modified"] = True
    
    try:
        sf = shapefile.Reader(target)
        records = sf.records()
        result["final_count"] = len(records)
        
        # Find POP_EST index
        field_names = [f[0] for f in sf.fields[1:]]
        try:
            pop_idx = next(i for i, name in enumerate(field_names) if name == 'POP_EST')
            
            invalid = 0
            valid = 0
            for r in records:
                if r[pop_idx] == -99:
                    invalid += 1
                else:
                    valid += 1
            
            result["invalid_remaining"] = invalid
            result["valid_remaining"] = valid
            
        except StopIteration:
            result["error"] = "POP_EST field missing in output"
            
    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "File not found"

# Load initial stats if available
try:
    with open('/tmp/initial_stats.json', 'r') as f:
        initial = json.load(f)
        result["initial_count"] = initial.get("initial_count", 0)
        result["initial_corrupted"] = initial.get("corrupted_count", 0)
except:
    result["initial_count"] = 0
    result["initial_corrupted"] = 0

# Write result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="