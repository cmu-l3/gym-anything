#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Priority Matrix Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Capture Final Matrix State from Database
echo "Querying final matrix state..."

SQL_QUERY="SELECT i.name, u.name, p.name 
FROM prioritymatrix pm 
JOIN impact i ON pm.impactid = i.impactid 
JOIN urgency u ON pm.urgencyid = u.urgencyid 
JOIN priority p ON pm.priorityid = p.priorityid 
ORDER BY i.name, u.name;"

# We use JSON_AGG if available, or just raw text processing. 
# Since postgres version might vary, let's use python to format the raw output to JSON safely.
RAW_OUTPUT=$(sdp_db_exec "$SQL_QUERY" "servicedesk")

# Convert pipe-delimited output to JSON using Python
FINAL_MATRIX_JSON=$(python3 -c "
import sys, json
lines = sys.stdin.readlines()
data = []
for line in lines:
    parts = line.strip().split('|')
    if len(parts) >= 3:
        data.append({'impact': parts[0], 'urgency': parts[1], 'priority': parts[2]})
print(json.dumps(data))
" <<< "$RAW_OUTPUT")

# 3. Read Initial State for comparison
INITIAL_RAW=$(cat /tmp/initial_matrix_state.txt 2>/dev/null || echo "")
INITIAL_MATRIX_JSON=$(python3 -c "
import sys, json
lines = sys.stdin.readlines()
data = []
for line in lines:
    parts = line.strip().split('|')
    if len(parts) >= 3:
        data.append({'impact': parts[0], 'urgency': parts[1], 'priority': parts[2]})
print(json.dumps(data))
" <<< "$INITIAL_RAW")

# 4. Check if SDP is still running
APP_RUNNING=$(pgrep -f "WrapperJVMMain" > /dev/null && echo "true" || echo "false")

# 5. Get Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "initial_matrix": $INITIAL_MATRIX_JSON,
    "final_matrix": $FINAL_MATRIX_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="