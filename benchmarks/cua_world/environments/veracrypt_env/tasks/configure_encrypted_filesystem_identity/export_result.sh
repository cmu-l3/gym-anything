#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Filesystem Identity Result ==="

VOLUME_PATH="/home/ga/Volumes/backup_tuesday.hc"
MOUNT_POINT="/tmp/vc_verify_mount"
RESULT_JSON="/tmp/task_result.json"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Initialize variables
VOLUME_EXISTS="false"
IS_MOUNTED_BY_AGENT="false"
MOUNT_SUCCESS="false"
FS_TYPE=""
FS_UUID=""
FS_LABEL=""
FILE_CONTENT_MATCH="false"
VOLUME_SIZE_MB=0
CREATED_DURING_TASK="false"

# 1. Check if volume exists
if [ -f "$VOLUME_PATH" ]; then
    VOLUME_EXISTS="true"
    
    # Check creation time (anti-gaming)
    FILE_MTIME=$(stat -c %Y "$VOLUME_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START_TIME" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Check size
    SIZE_BYTES=$(stat -c %s "$VOLUME_PATH" 2>/dev/null || echo "0")
    VOLUME_SIZE_MB=$((SIZE_BYTES / 1024 / 1024))
fi

# 2. Check if agent left it mounted (Task requires dismount)
MOUNT_LIST=$(veracrypt --text --list --non-interactive 2>&1 || echo "")
if echo "$MOUNT_LIST" | grep -q "$VOLUME_PATH"; then
    IS_MOUNTED_BY_AGENT="true"
    # Dismount it so we can mount it cleanly for verification
    veracrypt --text --dismount "$VOLUME_PATH" --non-interactive 2>/dev/null || true
    sleep 1
fi

# 3. Verification Mount
if [ "$VOLUME_EXISTS" = "true" ]; then
    mkdir -p "$MOUNT_POINT"
    
    echo "Attempting verification mount..."
    # Mount with password
    veracrypt --text --mount "$VOLUME_PATH" "$MOUNT_POINT" \
        --password='RotationSchedule2024!' \
        --pim=0 \
        --keyfiles="" \
        --protect-hidden=no \
        --non-interactive 2>/dev/null || true

    if mountpoint -q "$MOUNT_POINT"; then
        MOUNT_SUCCESS="true"
        
        # Identify the loop/mapper device
        # VeraCrypt usually maps to /dev/mapper/veracryptX
        # We can find the device associated with the mount point
        MAPPER_DEV=$(findmnt -n -o SOURCE --target "$MOUNT_POINT")
        
        echo "Mounted at $MOUNT_POINT on device $MAPPER_DEV"

        # 4. Inspect Filesystem Metadata (Label, UUID, Type)
        # We use blkid for robust detection
        if [ -n "$MAPPER_DEV" ]; then
            FS_TYPE=$(sudo blkid -o value -s TYPE "$MAPPER_DEV")
            FS_UUID=$(sudo blkid -o value -s UUID "$MAPPER_DEV")
            FS_LABEL=$(sudo blkid -o value -s LABEL "$MAPPER_DEV")
            
            # Fallback to tune2fs if blkid fails for ext4
            if [ -z "$FS_UUID" ] && [[ "$FS_TYPE" == *"ext"* ]]; then
                 FS_UUID=$(sudo tune2fs -l "$MAPPER_DEV" | grep "Filesystem UUID" | awk '{print $3}')
                 FS_LABEL=$(sudo tune2fs -l "$MAPPER_DEV" | grep "Filesystem volume name" | awk '{print $4}')
            fi
        fi

        # 5. Check Internal File
        if [ -f "$MOUNT_POINT/drive_info.txt" ]; then
            CONTENT=$(cat "$MOUNT_POINT/drive_info.txt")
            if [[ "$CONTENT" == *"PROPERTY OF OPS TEAM"* ]] && [[ "$CONTENT" == *"550e8400"* ]]; then
                FILE_CONTENT_MATCH="true"
            fi
        fi

        # Dismount verification mount
        veracrypt --text --dismount "$MOUNT_POINT" --non-interactive 2>/dev/null || true
    else
        echo "Failed to mount for verification"
    fi
    rmdir "$MOUNT_POINT" 2>/dev/null || true
fi

# 6. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 7. Write JSON Result
cat > "$RESULT_JSON" << EOF
{
    "volume_exists": $VOLUME_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "volume_size_mb": $VOLUME_SIZE_MB,
    "left_mounted": $IS_MOUNTED_BY_AGENT,
    "mount_success": $MOUNT_SUCCESS,
    "fs_type": "$FS_TYPE",
    "fs_uuid": "$FS_UUID",
    "fs_label": "$FS_LABEL",
    "file_content_match": $FILE_CONTENT_MATCH,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Result saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="