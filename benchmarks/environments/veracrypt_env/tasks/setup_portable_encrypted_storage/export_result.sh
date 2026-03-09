#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Portable Encrypted Storage Result ==="

TARGET_DIR="/home/ga/PortableDrive"
VOL_NAME="secure_storage.hc"
VOL_PATH="$TARGET_DIR/$VOL_NAME"
PASSWORD="Tr@vel3r2024!"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# --- 1. Check Directory Structure ---
DIR_EXISTS="false"
HAS_BINARY="false"
HAS_MNT="false"
HAS_VOL="false"
HAS_MOUNT_SH="false"
HAS_UNMOUNT_SH="false"
HAS_README="false"

if [ -d "$TARGET_DIR" ]; then
    DIR_EXISTS="true"
    [ -f "$TARGET_DIR/veracrypt" ] && [ -x "$TARGET_DIR/veracrypt" ] && HAS_BINARY="true"
    [ -d "$TARGET_DIR/mnt" ] && HAS_MNT="true"
    [ -f "$VOL_PATH" ] && HAS_VOL="true"
    [ -f "$TARGET_DIR/mount.sh" ] && HAS_MOUNT_SH="true"
    [ -f "$TARGET_DIR/unmount.sh" ] && HAS_UNMOUNT_SH="true"
    [ -f "$TARGET_DIR/README.txt" ] && HAS_README="true"
fi

# --- 2. Check Volume Properties ---
VOL_SIZE_MB=0
VOL_CREATED_DURING_TASK="false"
VOL_VALID="false"

if [ "$HAS_VOL" = "true" ]; then
    SIZE_BYTES=$(stat -c%s "$VOL_PATH")
    VOL_SIZE_MB=$((SIZE_BYTES / 1024 / 1024))
    
    FILE_MTIME=$(stat -c%Y "$VOL_PATH")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        VOL_CREATED_DURING_TASK="true"
    fi
fi

# --- 3. Functional Testing of Scripts & Volume ---
# We will attempt to run the user's scripts to see if they work as verified
SCRIPT_MOUNT_SUCCESS="false"
SCRIPT_UNMOUNT_SUCCESS="false"
MANUAL_MOUNT_SUCCESS="false"
CONTENT_OS_RELEASE="false"
CONTENT_HOSTNAME="false"
USING_LOCAL_BINARY="false"

# Check if mount.sh uses ./veracrypt (grep check)
if [ "$HAS_MOUNT_SH" = "true" ]; then
    if grep -q "\./veracrypt" "$TARGET_DIR/mount.sh"; then
        USING_LOCAL_BINARY="true"
    fi
fi

# Verify Volume Content (Test Mount)
# First, ensure it's not already mounted by the agent
if mount | grep -q "$TARGET_DIR/mnt"; then
    WAS_MOUNTED_AT_END="true"
    # It's already mounted, so we can check contents directly
    [ -f "$TARGET_DIR/mnt/os-release" ] && diff "$TARGET_DIR/mnt/os-release" /etc/os-release >/dev/null && CONTENT_OS_RELEASE="true"
    [ -f "$TARGET_DIR/mnt/hostname" ] && diff "$TARGET_DIR/mnt/hostname" /etc/hostname >/dev/null && CONTENT_HOSTNAME="true"
    
    # Try their unmount script
    cd "$TARGET_DIR" || true
    if [ "$HAS_UNMOUNT_SH" = "true" ] && [ -x "./unmount.sh" ]; then
        if ./unmount.sh >/dev/null 2>&1; then
            # Check if actually unmounted
            if ! mount | grep -q "$TARGET_DIR/mnt"; then
                SCRIPT_UNMOUNT_SUCCESS="true"
            fi
        fi
    fi
    # Force unmount if script failed
    veracrypt --text --dismount "$TARGET_DIR/mnt" --non-interactive 2>/dev/null || true
else
    WAS_MOUNTED_AT_END="false"
    
    # Try to mount using their script
    if [ "$HAS_MOUNT_SH" = "true" ] && [ -x "$TARGET_DIR/mount.sh" ]; then
        cd "$TARGET_DIR" || true
        # Run their script with password argument
        if ./mount.sh "$PASSWORD" >/dev/null 2>&1; then
             # Check if mounted
             if mount | grep -q "$TARGET_DIR/mnt"; then
                 SCRIPT_MOUNT_SUCCESS="true"
             fi
        fi
    fi
    
    # If script failed, try manual mount to verify volume integrity
    if [ "$SCRIPT_MOUNT_SUCCESS" = "false" ] && [ "$HAS_VOL" = "true" ]; then
        mkdir -p /tmp/vc_test_mount
        if veracrypt --text --mount "$VOL_PATH" /tmp/vc_test_mount --password="$PASSWORD" --pim=0 --keyfiles="" --protect-hidden=no --non-interactive >/dev/null 2>&1; then
            MANUAL_MOUNT_SUCCESS="true"
            VOL_VALID="true"
            # Check contents in manual mount
            [ -f "/tmp/vc_test_mount/os-release" ] && diff "/tmp/vc_test_mount/os-release" /etc/os-release >/dev/null && CONTENT_OS_RELEASE="true"
            [ -f "/tmp/vc_test_mount/hostname" ] && diff "/tmp/vc_test_mount/hostname" /etc/hostname >/dev/null && CONTENT_HOSTNAME="true"
            
            veracrypt --text --dismount /tmp/vc_test_mount --non-interactive >/dev/null 2>&1 || true
            rmdir /tmp/vc_test_mount 2>/dev/null || true
        fi
    elif [ "$SCRIPT_MOUNT_SUCCESS" = "true" ]; then
        # Script worked, check contents at their mount point
        MANUAL_MOUNT_SUCCESS="true" # Implicitly true if script worked
        VOL_VALID="true"
        [ -f "$TARGET_DIR/mnt/os-release" ] && diff "$TARGET_DIR/mnt/os-release" /etc/os-release >/dev/null && CONTENT_OS_RELEASE="true"
        [ -f "$TARGET_DIR/mnt/hostname" ] && diff "$TARGET_DIR/mnt/hostname" /etc/hostname >/dev/null && CONTENT_HOSTNAME="true"
        
        # Now test unmount script since we are mounted
        if [ "$HAS_UNMOUNT_SH" = "true" ] && [ -x "$TARGET_DIR/unmount.sh" ]; then
            if ./unmount.sh >/dev/null 2>&1; then
                if ! mount | grep -q "$TARGET_DIR/mnt"; then
                    SCRIPT_UNMOUNT_SUCCESS="true"
                fi
            fi
        fi
        # Cleanup
        veracrypt --text --dismount "$TARGET_DIR/mnt" --non-interactive >/dev/null 2>&1 || true
    fi
fi

# --- 4. Check README Content ---
README_CONTENT_OK="false"
if [ "$HAS_README" = "true" ]; then
    if grep -qi "Portable Encrypted Storage" "$TARGET_DIR/README.txt" && \
       grep -q "mount.sh" "$TARGET_DIR/README.txt" && \
       grep -q "unmount.sh" "$TARGET_DIR/README.txt"; then
        README_CONTENT_OK="true"
    fi
fi

# --- 5. Final Cleanup ---
# Ensure everything is definitely unmounted
veracrypt --text --dismount --non-interactive >/dev/null 2>&1 || true

# --- 6. Export JSON ---
take_screenshot /tmp/task_final.png

RESULT_JSON=$(cat << EOF
{
    "dir_exists": $DIR_EXISTS,
    "has_binary": $HAS_BINARY,
    "has_mnt": $HAS_MNT,
    "has_vol": $HAS_VOL,
    "has_mount_sh": $HAS_MOUNT_SH,
    "has_unmount_sh": $HAS_UNMOUNT_SH,
    "has_readme": $HAS_README,
    "vol_size_mb": $VOL_SIZE_MB,
    "vol_created_during_task": $VOL_CREATED_DURING_TASK,
    "vol_valid": $VOL_VALID,
    "script_mount_success": $SCRIPT_MOUNT_SUCCESS,
    "script_unmount_success": $SCRIPT_UNMOUNT_SUCCESS,
    "manual_mount_success": $MANUAL_MOUNT_SUCCESS,
    "content_os_release": $CONTENT_OS_RELEASE,
    "content_hostname": $CONTENT_HOSTNAME,
    "using_local_binary": $USING_LOCAL_BINARY,
    "readme_content_ok": $README_CONTENT_OK,
    "was_mounted_at_end": $WAS_MOUNTED_AT_END,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$CURRENT_TIME"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="