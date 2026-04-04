#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

# 1. Verification Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_FEED_ID=$(cat /tmp/initial_feed_id.txt 2>/dev/null || echo "0")
APIKEY=$(get_apikey_write)
BACKUP_PATH="/home/ga/attic_temp_backup.csv"

# Check Backup File
BACKUP_EXISTS=false
BACKUP_SIZE=0
BACKUP_TIME=0
if [ -f "$BACKUP_PATH" ]; then
    BACKUP_EXISTS=true
    BACKUP_SIZE=$(stat -c %s "$BACKUP_PATH")
    BACKUP_TIME=$(stat -c %Y "$BACKUP_PATH")
fi

# Check Current Feed State
# Find feed with name "attic_temp"
FEED_JSON=$(curl -s "${EMONCMS_URL}/feed/list.json?apikey=${APIKEY}" | jq '.[] | select(.name=="attic_temp")')
CURRENT_FEED_ID=$(echo "$FEED_JSON" | jq -r '.id')
CURRENT_FEED_INTERVAL=$(echo "$FEED_JSON" | jq -r '.interval')

# Check Input Process State
# Find input attic:temp
INPUT_JSON=$(curl -s "${EMONCMS_URL}/input/list.json?apikey=${APIKEY}" | jq '.[] | select(.nodeid=="attic" and .name=="temp")')
INPUT_PROCESS_LIST=$(echo "$INPUT_JSON" | jq -r '.processList')

# Take Final Screenshot
take_screenshot /tmp/task_final.png

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START,
    "backup": {
        "exists": $BACKUP_EXISTS,
        "size_bytes": $BACKUP_SIZE,
        "mod_time": $BACKUP_TIME,
        "path": "$BACKUP_PATH"
    },
    "initial_feed_id": $INITIAL_FEED_ID,
    "current_feed": {
        "id": ${CURRENT_FEED_ID:-null},
        "interval": ${CURRENT_FEED_INTERVAL:-0}
    },
    "input": {
        "process_list": "$INPUT_PROCESS_LIST"
    }
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json