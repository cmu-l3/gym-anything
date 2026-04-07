#!/bin/bash
echo "=== Exporting restore_camera_config result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Check for Restore Log
LOG_FILE="/home/ga/Documents/restore_log.txt"
LOG_EXISTS="false"
LOG_CONTENT=""
if [ -f "$LOG_FILE" ]; then
    LOG_EXISTS="true"
    # Read first 500 chars, escape quotes for JSON
    LOG_CONTENT=$(head -c 500 "$LOG_FILE" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))')
    # Remove outer quotes added by json.dumps since we insert it into json template
    LOG_CONTENT=${LOG_CONTENT:1:-1}
fi

# 3. Get the "Truth" (The backup file provided to the agent)
BACKUP_FILE="/home/ga/Documents/camera_backup.json"
BACKUP_DATA="{}"
if [ -f "$BACKUP_FILE" ]; then
    BACKUP_DATA=$(cat "$BACKUP_FILE")
fi

# 4. Get the "Current State" (Query API)
refresh_nx_token > /dev/null 2>&1 || true
CURRENT_STATE=$(get_all_cameras)

# 5. Check timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
LOG_MTIME=$(stat -c %Y "$LOG_FILE" 2>/dev/null || echo "0")

LOG_CREATED_DURING_TASK="false"
if [ "$LOG_MTIME" -gt "$TASK_START" ]; then
    LOG_CREATED_DURING_TASK="true"
fi

# 6. Bundle into JSON
# We use a python script to assemble the final JSON to avoid bash string escaping hell
python3 -c "
import json
import sys

try:
    backup = json.loads('''$BACKUP_DATA''')
except:
    backup = {}

try:
    current = json.loads('''$CURRENT_STATE''')
except:
    current = []

result = {
    'task_start': $TASK_START,
    'log_exists': $LOG_EXISTS,
    'log_created_during_task': $LOG_CREATED_DURING_TASK,
    'log_content_sample': '''$LOG_CONTENT''',
    'backup_configuration': backup,
    'final_system_state': current,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions so the host can copy it
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"