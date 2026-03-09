#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Camouflaged Volume Result ==="

TARGET_PATH="/home/ga/Volumes/legacy_driver_backup.iso"
EXPECTED_FILE="exploit_poc.py"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Basic File Checks
FILE_EXISTS="false"
FILE_SIZE_BYTES=0
FILE_MTIME_EPOCH=0
FILE_MTIME_STR=""
FILE_CTIME_EPOCH=0

if [ -f "$TARGET_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c%s "$TARGET_PATH" 2>/dev/null || echo "0")
    # Modification time (what the user should have changed)
    FILE_MTIME_EPOCH=$(stat -c%Y "$TARGET_PATH" 2>/dev/null || echo "0")
    FILE_MTIME_STR=$(stat -c%y "$TARGET_PATH" 2>/dev/null || echo "")
    # Change time (metadata change time - usually reflects when chmod/chown/touch happened)
    # This helps us verify the file was actually touched *during* the task
    FILE_CTIME_EPOCH=$(stat -c%Z "$TARGET_PATH" 2>/dev/null || echo "0")
fi

# 2. Check if currently mounted (it shouldn't be)
IS_MOUNTED_NOW="false"
MOUNT_LIST=$(veracrypt --text --list --non-interactive 2>&1 || echo "")
if echo "$MOUNT_LIST" | grep -q "$TARGET_PATH"; then
    IS_MOUNTED_NOW="true"
fi

# 3. Verification Mount
# Attempt to mount to verify it's a valid container and check content
VOLUME_VALID="false"
CONTENT_FOUND="false"
MOUNT_TEST_DIR="/tmp/vc_verify_camouflage"

mkdir -p "$MOUNT_TEST_DIR"

# If it's already mounted, force dismount first for clean test
if [ "$IS_MOUNTED_NOW" = "true" ]; then
    veracrypt --text --dismount "$TARGET_PATH" --non-interactive 2>/dev/null || true
    sleep 1
fi

if [ "$FILE_EXISTS" = "true" ]; then
    echo "Attempting verification mount..."
    if veracrypt --text --mount "$TARGET_PATH" "$MOUNT_TEST_DIR" \
        --password='Camouflage2024!' \
        --pim=0 \
        --keyfiles="" \
        --protect-hidden=no \
        --non-interactive > /dev/null 2>&1; then
        
        VOLUME_VALID="true"
        
        # Check content
        if [ -f "$MOUNT_TEST_DIR/$EXPECTED_FILE" ]; then
            CONTENT_FOUND="true"
        fi
        
        # Dismount
        veracrypt --text --dismount "$MOUNT_TEST_DIR" --non-interactive 2>/dev/null || true
    else
        echo "Verification mount failed."
    fi
fi
rmdir "$MOUNT_TEST_DIR" 2>/dev/null || true

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Export JSON
RESULT_JSON=$(cat << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_path": "$TARGET_PATH",
    "file_size_bytes": $FILE_SIZE_BYTES,
    "mtime_epoch": $FILE_MTIME_EPOCH,
    "mtime_str": "$FILE_MTIME_STR",
    "ctime_epoch": $FILE_CTIME_EPOCH,
    "task_start_time": $TASK_START,
    "volume_valid": $VOLUME_VALID,
    "content_found": $CONTENT_FOUND,
    "is_mounted_at_end": $IS_MOUNTED_NOW,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="