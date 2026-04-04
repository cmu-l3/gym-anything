#!/bin/bash
echo "=== Exporting size_rotor_for_5kw_output results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROJECT_PATH="/home/ga/Documents/projects/sized_rotor_5kw.wpa"
SIM_PATH="/home/ga/Documents/projects/final_simulation.txt"
RESULT_TXT_PATH="/home/ga/Documents/projects/sizing_result.txt"

# --- Check Project File ---
if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$PROJECT_PATH")
    PROJECT_MTIME=$(stat -c %Y "$PROJECT_PATH")
else
    PROJECT_EXISTS="false"
    PROJECT_SIZE=0
    PROJECT_MTIME=0
fi

# --- Check Simulation Export ---
SIM_EXISTS="false"
SIM_CONTENT=""
SIM_POWER_VAL=""
if [ -f "$SIM_PATH" ]; then
    SIM_EXISTS="true"
    # Read first 50 lines to keep JSON size manageable, but enough to capture data headers and first row
    SIM_CONTENT=$(head -n 50 "$SIM_PATH" | base64 -w 0)
    
    # Attempt to extract Power value from file using grep/awk
    # Typical QBlade export has a header row and data rows.
    # Looking for columns like "Power [W]" or similar.
    # We will let python do the heavy parsing, but we can grab the last non-empty line here
    LAST_LINE=$(grep -v "^$" "$SIM_PATH" | tail -n 1)
    SIM_LAST_LINE="$LAST_LINE"
else
    SIM_LAST_LINE=""
fi

# --- Check Result Text File ---
TXT_EXISTS="false"
TXT_CONTENT=""
if [ -f "$RESULT_TXT_PATH" ]; then
    TXT_EXISTS="true"
    TXT_CONTENT=$(cat "$RESULT_TXT_PATH")
fi

# --- Check App State ---
APP_RUNNING=$(pgrep -f "QBlade" > /dev/null && echo "true" || echo "false")

# --- Final Screenshot ---
take_screenshot /tmp/task_final.png

# --- Construct JSON ---
# We use a python one-liner to generate valid JSON to avoid shell escaping hell
python3 -c "
import json
import os

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'project': {
        'exists': $PROJECT_EXISTS,
        'size': $PROJECT_SIZE,
        'mtime': $PROJECT_MTIME
    },
    'simulation': {
        'exists': $SIM_EXISTS,
        'content_b64': '$SIM_CONTENT',
        'last_line': '''$SIM_LAST_LINE'''
    },
    'result_text': {
        'exists': $TXT_EXISTS,
        'content': '''$TXT_CONTENT'''
    },
    'app_running': $APP_RUNNING,
    'screenshot_path': '/tmp/task_final.png'
}
print(json.dumps(data))
" > /tmp/task_result.json

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="