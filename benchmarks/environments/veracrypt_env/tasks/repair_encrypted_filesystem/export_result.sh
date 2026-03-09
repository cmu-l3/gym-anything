#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Repair Encrypted Filesystem Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RECOVERY_FILE="/home/ga/Documents/recovered/investigation_notes.txt"
VOLUME_PATH="/home/ga/Volumes/broken_drive.hc"

# 1. Check if recovered file exists
FILE_EXISTS="false"
FILE_HASH=""
FILE_SIZE=0
CREATED_DURING_TASK="false"

if [ -f "$RECOVERY_FILE" ]; then
    FILE_EXISTS="true"
    FILE_HASH=$(md5sum "$RECOVERY_FILE" | awk '{print $1}')
    FILE_SIZE=$(stat -c%s "$RECOVERY_FILE")
    FILE_MTIME=$(stat -c%Y "$RECOVERY_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 2. Check if volume is currently valid/mountable (did they fix it?)
# We attempt to mount it normally to a temporary location
VOLUME_REPAIRED="false"
mkdir -p /tmp/vc_check_repair

# Try mounting normally (without filesystem=none)
if veracrypt --text --mount "$VOLUME_PATH" /tmp/vc_check_repair \
    --password='Journalist2024!' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive 2>/dev/null; then
    
    # If mount succeeds, check if we can list files (fs is actually working)
    if ls -la /tmp/vc_check_repair | grep -q "investigation_notes.txt"; then
        VOLUME_REPAIRED="true"
    fi
    
    veracrypt --text --dismount /tmp/vc_check_repair --non-interactive 2>/dev/null || true
fi
rmdir /tmp/vc_check_repair 2>/dev/null || true

# 3. Check for evidence of fsck usage in bash history
# (This is soft evidence, as they might have used other tools or cleaned history)
FSCK_USED="false"
if grep -E "fsck|dosfsck|mkfs" /home/ga/.bash_history 2>/dev/null; then
    FSCK_USED="true"
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON result
RESULT_JSON=$(cat << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_hash": "$FILE_HASH",
    "file_size": $FILE_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "volume_repaired": $VOLUME_REPAIRED,
    "fsck_used_history": $FSCK_USED,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="