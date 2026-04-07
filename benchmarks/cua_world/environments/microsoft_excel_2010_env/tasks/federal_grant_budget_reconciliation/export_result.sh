#!/bin/bash
echo "=== Exporting Task Results ==="

# 1. Define paths
OUTPUT_FILE="/home/ga/Documents/nsf_grant_ledger.xlsx"
RESULT_JSON="/tmp/task_result.json"
TASK_START_FILE="/tmp/task_start_time.txt"

# 2. Get Timestamps
TASK_END=$(date +%s)
if [ -f "$TASK_START_FILE" ]; then
    TASK_START=$(cat "$TASK_START_FILE")
else
    TASK_START=0
fi

# 3. Check file status
OUTPUT_EXISTS="false"
FILE_MODIFIED="false"
OUTPUT_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    # Check if modified after start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 4. Check App Status
APP_RUNNING="false"
if pgrep -f "EXCEL.EXE" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 6. Create JSON
# Use python to properly format JSON and handle boolean values
python3 -c "
import json
result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'output_exists': $OUTPUT_EXISTS, # python bool from bash string if true/false passed correctly
    'file_modified': $FILE_MODIFIED,
    'output_size_bytes': $OUTPUT_SIZE,
    'app_was_running': $APP_RUNNING,
    'screenshot_path': '/tmp/task_final.png',
    'ground_truth_direct': 0.0,
    'ground_truth_fa': 0.0
}

# Try to inject ground truth if available
try:
    with open('/tmp/ground_truth_values.txt', 'r') as f:
        d, fa = f.read().strip().split(',')
        result['ground_truth_direct'] = float(d)
        result['ground_truth_fa'] = float(fa)
except:
    pass

# Convert strings 'true'/'false' to booleans if needed, or just let them be
with open('$RESULT_JSON', 'w') as f:
    json.dump(result, f)
"

# 7. Set permissions so verifier can read it
chmod 666 "$RESULT_JSON"
echo "Export complete. Result saved to $RESULT_JSON"