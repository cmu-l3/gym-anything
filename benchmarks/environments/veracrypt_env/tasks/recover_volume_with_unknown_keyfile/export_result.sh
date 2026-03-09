#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Recover Volume Result ==="

# Paths
VOL_PATH="/home/ga/Volumes/project_archive.hc"
MOUNT_POINT="/home/ga/MountPoints/slot1"
USER_TOKEN_FILE="/home/ga/Documents/recovered_token.txt"
USER_KEYNAME_FILE="/home/ga/Documents/correct_keyfile_name.txt"
GROUND_TRUTH_KEY="/var/lib/app/ground_truth_keyname.txt"
GROUND_TRUTH_TOKEN="/var/lib/app/ground_truth_token.txt"

# 1. Check if Volume is Mounted
IS_MOUNTED="false"
MOUNT_LIST=$(veracrypt --text --list --non-interactive 2>&1 || echo "")
if echo "$MOUNT_LIST" | grep -q "$VOL_PATH" && echo "$MOUNT_LIST" | grep -q "$MOUNT_POINT"; then
    IS_MOUNTED="true"
fi

# 2. Check Token Recovery
TOKEN_RECOVERED="false"
TOKEN_MATCH="false"
ACTUAL_TOKEN=""
EXPECTED_TOKEN=""

if [ -f "$GROUND_TRUTH_TOKEN" ]; then
    EXPECTED_TOKEN=$(cat "$GROUND_TRUTH_TOKEN")
fi

if [ -f "$USER_TOKEN_FILE" ]; then
    ACTUAL_TOKEN=$(cat "$USER_TOKEN_FILE")
    if [ "$ACTUAL_TOKEN" == "$EXPECTED_TOKEN" ]; then
        TOKEN_MATCH="true"
    fi
    TOKEN_RECOVERED="true"
fi

# 3. Check Keyfile Identification
KEY_IDENTIFIED="false"
KEY_MATCH="false"
ACTUAL_KEYNAME=""
EXPECTED_KEYNAME=""

if [ -f "$GROUND_TRUTH_KEY" ]; then
    EXPECTED_KEYNAME=$(cat "$GROUND_TRUTH_KEY")
fi

if [ -f "$USER_KEYNAME_FILE" ]; then
    KEY_IDENTIFIED="true"
    # Read first line, trim whitespace
    ACTUAL_KEYNAME=$(head -n 1 "$USER_KEYNAME_FILE" | tr -d '[:space:]')
    
    # Simple string comparison
    if [ "$ACTUAL_KEYNAME" == "$EXPECTED_KEYNAME" ]; then
        KEY_MATCH="true"
    fi
fi

# 4. Anti-gaming: Check file timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILES_NEW="false"

if [ -f "$USER_TOKEN_FILE" ]; then
    FILE_TIME=$(stat -c %Y "$USER_TOKEN_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -ge "$TASK_START" ]; then
        FILES_NEW="true"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_end.png

# Create result JSON
RESULT_JSON=$(cat << EOF
{
    "is_mounted": $IS_MOUNTED,
    "token_file_exists": $TOKEN_RECOVERED,
    "token_match": $TOKEN_MATCH,
    "keyfile_report_exists": $KEY_IDENTIFIED,
    "keyfile_match": $KEY_MATCH,
    "files_created_during_task": $FILES_NEW,
    "expected_keyname": "$EXPECTED_KEYNAME",
    "actual_keyname": "$ACTUAL_KEYNAME",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="