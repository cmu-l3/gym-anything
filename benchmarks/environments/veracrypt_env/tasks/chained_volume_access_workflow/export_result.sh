#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Chained Volume Task Result ==="

TARGET_FILE="/home/ga/Documents/recovered_coordinates.csv"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if target file exists and get MD5
FILE_EXISTS="false"
FILE_MD5=""
FILE_SIZE=0
CREATED_DURING_TASK="false"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MD5=$(md5sum "$TARGET_FILE" | awk '{print $1}')
    FILE_SIZE=$(stat -c%s "$TARGET_FILE")
    
    # Check timestamp
    FILE_MTIME=$(stat -c%Y "$TARGET_FILE")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 2. Check if cleanup was performed (no volumes mounted)
# veracrypt --text --list returns empty string if nothing mounted, or "No volumes mounted" depending on version
# or it lists the mounts.
MOUNT_LIST=$(veracrypt --text --list --non-interactive 2>&1 || echo "")
IS_CLEAN="false"

# Count lines that start with a digit (slot number)
MOUNT_COUNT=$(echo "$MOUNT_LIST" | grep -c "^[0-9]" || echo "0")

if [ "$MOUNT_COUNT" -eq "0" ]; then
    IS_CLEAN="true"
fi

# 3. Check for any intermediate keyfiles left on disk (security risk check - optional but good for scoring context)
BETA_KEY_LEFT="false"
GAMMA_KEY_LEFT="false"
if [ -f "/home/ga/beta_token.jpg" ] || [ -f "/home/ga/Documents/beta_token.jpg" ]; then BETA_KEY_LEFT="true"; fi
if [ -f "/home/ga/gamma_token.wav" ] || [ -f "/home/ga/Documents/gamma_token.wav" ]; then GAMMA_KEY_LEFT="true"; fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
RESULT_JSON=$(cat << EOF
{
    "target_file_exists": $FILE_EXISTS,
    "target_file_md5": "$FILE_MD5",
    "target_file_size": $FILE_SIZE,
    "file_created_during_task": $CREATED_DURING_TASK,
    "is_clean_state": $IS_CLEAN,
    "mounted_volume_count": $MOUNT_COUNT,
    "beta_key_exposed": $BETA_KEY_LEFT,
    "gamma_key_exposed": $GAMMA_KEY_LEFT,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="