#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Secure Mount Permissions Result ==="

MOUNT_POINT="/home/ga/MountPoints/project"
VOLUME_PATH="/home/ga/Volumes/project_alpha.hc"
TEST_FILE="$MOUNT_POINT/access_test.txt"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check if mounted
IS_MOUNTED="false"
if mountpoint -q "$MOUNT_POINT"; then
    IS_MOUNTED="true"
fi

# 3. Collect File System Stats (Ownership & Permissions)
# Format: %u (uid), %g (gid), %a (octal perms), %A (human perms)
DIR_STATS=$(stat -c "%u|%g|%a|%A" "$MOUNT_POINT" 2>/dev/null || echo "0|0|0|0")
DIR_UID=$(echo "$DIR_STATS" | cut -d'|' -f1)
DIR_GID=$(echo "$DIR_STATS" | cut -d'|' -f2)
DIR_OCTAL=$(echo "$DIR_STATS" | cut -d'|' -f3)
DIR_HUMAN=$(echo "$DIR_STATS" | cut -d'|' -f4)

# Check a file inside (if exists)
SAMPLE_FILE="$MOUNT_POINT/README.md"
FILE_STATS=$(stat -c "%u|%g|%a|%A" "$SAMPLE_FILE" 2>/dev/null || echo "0|0|0|0")
FILE_UID=$(echo "$FILE_STATS" | cut -d'|' -f1)
FILE_GID=$(echo "$FILE_STATS" | cut -d'|' -f2)
FILE_OCTAL=$(echo "$FILE_STATS" | cut -d'|' -f3)
FILE_HUMAN=$(echo "$FILE_STATS" | cut -d'|' -f4)

# 4. Check for Agent's Test File
AGENT_TEST_FILE_EXISTS="false"
AGENT_TEST_FILE_UID="0"
if [ -f "$TEST_FILE" ]; then
    AGENT_TEST_FILE_EXISTS="true"
    AGENT_TEST_FILE_UID=$(stat -c "%u" "$TEST_FILE" 2>/dev/null || echo "0")
fi

# 5. Check actual write capability (Verification Script attempts to write)
# We try to write as user 'ga'
CAN_WRITE="false"
if [ "$IS_MOUNTED" = "true" ]; then
    if sudo -u ga touch "$MOUNT_POINT/verifier_probe.txt" 2>/dev/null; then
        CAN_WRITE="true"
        rm -f "$MOUNT_POINT/verifier_probe.txt"
    fi
fi

# 6. Get Mount Options from system
MOUNT_OPTS=$(mount | grep "$MOUNT_POINT" | grep "veracrypt" || echo "")

# 7. Create JSON Result
RESULT_JSON=$(cat << EOF
{
    "is_mounted": $IS_MOUNTED,
    "mount_point": "$MOUNT_POINT",
    "dir_uid": $DIR_UID,
    "dir_gid": $DIR_GID,
    "dir_octal": "$DIR_OCTAL",
    "dir_human": "$DIR_HUMAN",
    "file_uid": $FILE_UID,
    "file_gid": $FILE_GID,
    "file_octal": "$FILE_OCTAL",
    "file_human": "$FILE_HUMAN",
    "agent_test_file_exists": $AGENT_TEST_FILE_EXISTS,
    "agent_test_file_uid": $AGENT_TEST_FILE_UID,
    "can_write_as_ga": $CAN_WRITE,
    "mount_options_raw": "$(echo "$MOUNT_OPTS" | sed 's/"/\\"/g')",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="