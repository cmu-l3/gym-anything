#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Cross-Platform Volume Result ==="

VOLUME_PATH="/home/ga/Volumes/dailies_transfer.hc"
MANIFEST_NAME="production_manifest.csv"
EXPECTED_PASSWORD="ProductionSafe2024!"

# Init result variables
VOLUME_EXISTS="false"
VOLUME_SIZE_MB=0
PASSWORD_WORKS="false"
FILESYSTEM_TYPE="unknown"
MANIFEST_FOUND="false"
IS_DISMOUNTED="true"
CREATED_DURING_TASK="false"

# 1. Check file existence and size
if [ -f "$VOLUME_PATH" ]; then
    VOLUME_EXISTS="true"
    SIZE_BYTES=$(stat -c%s "$VOLUME_PATH")
    VOLUME_SIZE_MB=$((SIZE_BYTES / 1024 / 1024))
    
    # Check creation time vs task start
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    FILE_CTIME=$(stat -c%Y "$VOLUME_PATH")
    if [ "$FILE_CTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 2. Check if the agent left it mounted (should be dismounted)
# We check all slots. If mounted, we use that mount point to verify, but verify logic penalizes not dismounting.
EXISTING_MOUNT=$(veracrypt --text --list | grep "$VOLUME_PATH" | awk '{print $3}' | head -n 1)

VERIFY_MOUNT_POINT="/tmp/vc_verify_cross_platform"
NEEDS_DISMOUNT_VERIFY="false"

if [ -n "$EXISTING_MOUNT" ]; then
    echo "Volume currently mounted by agent at $EXISTING_MOUNT"
    IS_DISMOUNTED="false"
    VERIFY_MOUNT_POINT="$EXISTING_MOUNT"
    PASSWORD_WORKS="true" # If it's already mounted, auth succeeded
else
    # 3. Try to mount it ourselves to verify password and filesystem
    echo "Volume not mounted. Attempting verification mount..."
    mkdir -p "$VERIFY_MOUNT_POINT"
    
    if veracrypt --text --mount "$VOLUME_PATH" "$VERIFY_MOUNT_POINT" \
        --password="$EXPECTED_PASSWORD" \
        --pim=0 --keyfiles="" --protect-hidden=no --non-interactive >/dev/null 2>&1; then
        PASSWORD_WORKS="true"
        NEEDS_DISMOUNT_VERIFY="true"
    else
        echo "Failed to mount with expected password."
    fi
fi

# 4. Inspect Filesystem and Content (if mounted successfully)
if [ "$PASSWORD_WORKS" = "true" ]; then
    # Check Filesystem Type
    # use -f to get full fs info, look for exfat
    # Alternative: findmnt -n -o FSTYPE --target MOUNTPOINT
    if command -v findmnt >/dev/null; then
        FILESYSTEM_TYPE=$(findmnt -n -o FSTYPE --target "$VERIFY_MOUNT_POINT")
    else
        # Fallback to df -T
        FILESYSTEM_TYPE=$(df -T "$VERIFY_MOUNT_POINT" | tail -n 1 | awk '{print $2}')
    fi
    
    # Check Content
    if [ -f "$VERIFY_MOUNT_POINT/$MANIFEST_NAME" ]; then
        MANIFEST_FOUND="true"
    fi
    
    echo "Detected Filesystem: $FILESYSTEM_TYPE"
    echo "Manifest Found: $MANIFEST_FOUND"
fi

# 5. Cleanup verification mount
if [ "$NEEDS_DISMOUNT_VERIFY" = "true" ]; then
    veracrypt --text --dismount "$VERIFY_MOUNT_POINT" --non-interactive >/dev/null 2>&1 || true
    rmdir "$VERIFY_MOUNT_POINT" >/dev/null 2>&1 || true
fi

# 6. Final Screenshot
take_screenshot /tmp/task_final.png

# 7. Write Result JSON
RESULT_JSON=$(cat << EOF
{
    "volume_exists": $VOLUME_EXISTS,
    "volume_size_mb": $VOLUME_SIZE_MB,
    "created_during_task": $CREATED_DURING_TASK,
    "password_works": $PASSWORD_WORKS,
    "filesystem_type": "$FILESYSTEM_TYPE",
    "manifest_found": $MANIFEST_FOUND,
    "is_dismounted": $IS_DISMOUNTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"
echo "Result: $RESULT_JSON"

echo "=== Export Complete ==="