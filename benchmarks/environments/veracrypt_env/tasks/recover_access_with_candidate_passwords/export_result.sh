#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Access Recovery Result ==="

# Paths
RECOVERED_DIR="/home/ga/Documents/Recovered"
RECOVERED_FILE="$RECOVERED_DIR/Project_Alpha_Summary.pdf"
PASSWORD_FILE="$RECOVERED_DIR/correct_password.txt"
VOLUME_PATH="/home/ga/Volumes/project_alpha_archive.hc"

# 1. Check Recovered File
FILE_EXISTS="false"
FILE_HASH=""
FILE_SIZE=0

if [ -f "$RECOVERED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_HASH=$(sha256sum "$RECOVERED_FILE" | awk '{print $1}')
    FILE_SIZE=$(stat -c%s "$RECOVERED_FILE")
fi

# 2. Check Identified Password
IDENTIFIED_PASSWORD=""
PASSWORD_FILE_EXISTS="false"

if [ -f "$PASSWORD_FILE" ]; then
    PASSWORD_FILE_EXISTS="true"
    # Read first line, trim whitespace
    IDENTIFIED_PASSWORD=$(head -n 1 "$PASSWORD_FILE" | tr -d '[:space:]')
fi

# 3. Check Dismount Status
# Check if the specific volume file is currently mounted
MOUNT_INFO=$(veracrypt --text --list --non-interactive 2>&1 || echo "")
IS_MOUNTED="false"
if echo "$MOUNT_INFO" | grep -Fq "$VOLUME_PATH"; then
    IS_MOUNTED="true"
fi

# 4. Get Ground Truth (Read from the hidden file created in setup)
GROUND_TRUTH_FILE="/root/task_ground_truth.json"
CORRECT_PASSWORD=""
EXPECTED_HASH=""

if [ -f "$GROUND_TRUTH_FILE" ]; then
    # Parse simple JSON using grep/sed/awk to avoid python dependency issues if environment is minimal,
    # though python3 is available. Let's use python for reliability.
    CORRECT_PASSWORD=$(python3 -c "import json; print(json.load(open('$GROUND_TRUTH_FILE'))['correct_password'])" 2>/dev/null)
    EXPECTED_HASH=$(python3 -c "import json; print(json.load(open('$GROUND_TRUTH_FILE'))['expected_file_hash'])" 2>/dev/null)
fi

# 5. Timestamp Check
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MTIME=0
CREATED_DURING_TASK="false"

if [ "$FILE_EXISTS" = "true" ]; then
    FILE_MTIME=$(stat -c %Y "$RECOVERED_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 6. Take Screenshot
take_screenshot /tmp/task_end.png

# 7. Create Result JSON
# Escape strings
SAFE_IDENTIFIED=$(echo "$IDENTIFIED_PASSWORD" | sed 's/"/\\"/g')
SAFE_CORRECT=$(echo "$CORRECT_PASSWORD" | sed 's/"/\\"/g')

RESULT_JSON=$(cat << EOF
{
    "recovered_file_exists": $FILE_EXISTS,
    "recovered_file_hash": "$FILE_HASH",
    "recovered_file_size": $FILE_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "password_file_exists": $PASSWORD_FILE_EXISTS,
    "identified_password": "$SAFE_IDENTIFIED",
    "correct_password": "$SAFE_CORRECT",
    "expected_hash": "$EXPECTED_HASH",
    "volume_still_mounted": $IS_MOUNTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/recovery_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/recovery_result.json"
cat /tmp/recovery_result.json

echo "=== Export Complete ==="