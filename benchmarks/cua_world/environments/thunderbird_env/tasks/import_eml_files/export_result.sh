#!/bin/bash
echo "=== Exporting import_eml_files result ==="

# 1. Record timing and take final screenshot
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Give Thunderbird a moment to flush disk writes before checking files
sleep 3
pkill -f "thunderbird" 2>/dev/null || true
sleep 2

LOCAL_MAIL_DIR="/home/ga/.thunderbird/default-release/Mail/Local Folders"

# 2. Check for the specific folder variations
FOLDER_EXISTS="false"
FOLDER_NAME_FOUND=""
TARGET_MBOX=""

for variant in "Client Correspondence" "Client_Correspondence" "client correspondence"; do
    if [ -f "${LOCAL_MAIL_DIR}/${variant}" ]; then
        FOLDER_EXISTS="true"
        FOLDER_NAME_FOUND="$variant"
        TARGET_MBOX="${LOCAL_MAIL_DIR}/${variant}"
        break
    fi
done

# 3. Parse the mbox file using Python to safely extract contents
# This avoids doing complex bash parsing and allows direct JSON output
PARSE_RESULT=$(python3 -c "
import mailbox, json, sys, os

mbox_path = sys.argv[1]
result = {
    'count': 0,
    'subjects': [],
    'valid_headers': 0,
    'file_size': 0
}

if os.path.exists(mbox_path):
    result['file_size'] = os.path.getsize(mbox_path)
    try:
        mbox = mailbox.mbox(mbox_path)
        result['count'] = len(mbox)
        for msg in mbox:
            subj = str(msg.get('Subject', '')).replace('\n', '').replace('\r', '').strip()
            if subj:
                result['subjects'].append(subj)
            if msg.get('From') and msg.get('Date'):
                result['valid_headers'] += 1
    except Exception as e:
        result['error'] = str(e)

print(json.dumps(result))
" "$TARGET_MBOX" 2>/dev/null || echo '{"count": 0, "subjects": [], "valid_headers": 0, "file_size": 0}')

# 4. Load expected subjects into a JSON array string
EXPECTED_SUBJECTS_JSON=$(python3 -c "
import json, os
expected_file = '/tmp/expected_eml_subjects.txt'
if os.path.exists(expected_file):
    with open(expected_file, 'r') as f:
        print(json.dumps([line.strip() for line in f if line.strip()]))
else:
    print('[]')
")

# 5. Check if folder was created during the task (Anti-gaming check)
FOLDER_CREATED_DURING_TASK="false"
if [ "$FOLDER_EXISTS" = "true" ]; then
    FOLDER_MTIME=$(stat -c %Y "$TARGET_MBOX" 2>/dev/null || echo "0")
    if [ "$FOLDER_MTIME" -gt "$TASK_START" ]; then
        FOLDER_CREATED_DURING_TASK="true"
    fi
fi

# Check if Thunderbird is running
APP_RUNNING=$(pgrep -f "thunderbird" > /dev/null && echo "true" || echo "false")

# 6. Build the final JSON result safely using a temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "folder_exists": $FOLDER_EXISTS,
    "folder_name_found": "$FOLDER_NAME_FOUND",
    "folder_created_during_task": $FOLDER_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "mbox_data": $PARSE_RESULT,
    "expected_subjects": $EXPECTED_SUBJECTS_JSON,
    "screenshot_path": "/tmp/task_final.png"
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