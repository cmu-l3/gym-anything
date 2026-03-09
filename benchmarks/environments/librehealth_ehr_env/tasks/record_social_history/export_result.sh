#!/bin/bash
echo "=== Exporting Social History Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_PID=$(cat /tmp/task_target_pid.txt 2>/dev/null)

if [ -z "$TARGET_PID" ]; then
    echo "ERROR: Target PID not found."
    exit 1
fi

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Query Final Database State
# We fetch the most recent history record for this patient
CURRENT_HISTORY_JSON=$(docker exec librehealth-db mysql -u libreehr -ps3cret libreehr -N -e "
    SELECT JSON_OBJECT(
        'tobacco', tobacco,
        'alcohol', alcohol,
        'recreational_drugs', recreational_drugs,
        'exercise_patterns', exercise_patterns,
        'counseling', counseling,
        'date', date
    )
    FROM history_data
    WHERE pid = ${TARGET_PID}
    ORDER BY id DESC LIMIT 1;
" 2>/dev/null)

# 3. Check for app running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Construct Result JSON
# We include both initial and final states so the verifier can diff them
INITIAL_HISTORY_CONTENT=$(cat /tmp/task_initial_history.json 2>/dev/null || echo "{}")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import sys

try:
    initial = json.loads('''$INITIAL_HISTORY_CONTENT''')
except:
    initial = {}

try:
    final_state = json.loads('''$CURRENT_HISTORY_JSON''')
except:
    final_state = {}

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'target_pid': $TARGET_PID,
    'app_running': '$APP_RUNNING' == 'true',
    'initial_state': initial,
    'final_state': final_state,
    'screenshot_path': '/tmp/task_final.png'
}
print(json.dumps(result, indent=2))
" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="