#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting backup_volume_header task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
BACKUP_FILE="/home/ga/Volumes/data_volume_header_backup.bin"
ORIGINAL_VOLUME="/home/ga/Volumes/data_volume.hc"
ORIGINAL_CHECKSUM_FILE="/tmp/original_volume_checksum.txt"

# 1. Check Backup File Existence and Properties
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
FILE_PATH_USED=""

if [ -f "$BACKUP_FILE" ]; then
    FILE_EXISTS="true"
    FILE_PATH_USED="$BACKUP_FILE"
    FILE_SIZE=$(stat -c%s "$BACKUP_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$BACKUP_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
else
    # Check if they saved it with a slightly different name or extension
    for f in /home/ga/Volumes/*.bin /home/ga/Volumes/*.backup; do
        if [ -f "$f" ] && [ "$f" != "$ORIGINAL_VOLUME" ]; then
            MTIME=$(stat -c%Y "$f" 2>/dev/null || echo "0")
            if [ "$MTIME" -gt "$TASK_START" ]; then
                FILE_EXISTS="true"
                FILE_PATH_USED="$f"
                FILE_SIZE=$(stat -c%s "$f" 2>/dev/null || echo "0")
                FILE_CREATED_DURING_TASK="true"
                break
            fi
        fi
    done
fi

# 2. Check Original Volume Integrity
ORIGINAL_INTACT="false"
CURRENT_CHECKSUM=""
EXPECTED_CHECKSUM=""

if [ -f "$ORIGINAL_VOLUME" ] && [ -f "$ORIGINAL_CHECKSUM_FILE" ]; then
    CURRENT_CHECKSUM=$(sha256sum "$ORIGINAL_VOLUME" | awk '{print $1}')
    EXPECTED_CHECKSUM=$(cat "$ORIGINAL_CHECKSUM_FILE" | awk '{print $1}')
    
    if [ "$CURRENT_CHECKSUM" == "$EXPECTED_CHECKSUM" ]; then
        ORIGINAL_INTACT="true"
    fi
fi

# 3. Check if volume is left mounted (it should NOT be)
VOLUME_LEFT_MOUNTED="false"
if veracrypt --text --list | grep -q "data_volume"; then
    VOLUME_LEFT_MOUNTED="true"
fi

# 4. Functional Validation: Can this backup actually restore a volume?
# This is the most critical check. We copy the volume, corrupt it, then try to restore.
FUNCTIONAL_RESTORE_SUCCESS="false"
CORRUPT_VOLUME_MOUNT_FAILED="false"

if [ "$FILE_EXISTS" = "true" ] && [ "$ORIGINAL_INTACT" = "true" ]; then
    echo "Starting functional validation of backup file..."
    
    # Create temp copy of original volume
    TEST_VOL="/tmp/vc_restore_test.hc"
    cp "$ORIGINAL_VOLUME" "$TEST_VOL"
    
    # Corrupt the header (first 128KB is safe to zero out to destroy header)
    dd if=/dev/zero of="$TEST_VOL" bs=1024 count=128 conv=notrunc 2>/dev/null
    
    # Verify corrupted volume cannot mount
    mkdir -p /tmp/vc_test_mnt
    if ! veracrypt --text --mount "$TEST_VOL" /tmp/vc_test_mnt \
        --password='MountMe2024' --pim=0 --keyfiles='' --protect-hidden=no --non-interactive >/dev/null 2>&1; then
        CORRUPT_VOLUME_MOUNT_FAILED="true"
        echo "Validation: Corrupted volume failed to mount (expected)."
    else
        echo "Validation: Corrupted volume mounted unexpectedly!"
        veracrypt --text --dismount /tmp/vc_test_mnt --non-interactive 2>/dev/null || true
    fi
    
    # Attempt restore using the backup file
    # Note: CLI restore-headers requires interaction or specific input format
    # We use expect-style input via pipe
    # Input sequence: 2 (Restore from ext file), File path, Password
    
    # Using specific non-interactive flag if available, else piping input
    echo "Restoring header from $FILE_PATH_USED..."
    
    if veracrypt --text --restore-headers "$TEST_VOL" --backup-headers-file="$FILE_PATH_USED" \
        --password='MountMe2024' --pim=0 --keyfiles='' --non-interactive 2>/dev/null; then
        echo "Restore command executed successfully."
        
        # Now try to mount the restored volume
        if veracrypt --text --mount "$TEST_VOL" /tmp/vc_test_mnt \
            --password='MountMe2024' --pim=0 --keyfiles='' --protect-hidden=no --non-interactive 2>/dev/null; then
            if mountpoint -q /tmp/vc_test_mnt; then
                FUNCTIONAL_RESTORE_SUCCESS="true"
                echo "Validation: Restored volume mounted successfully!"
            fi
            veracrypt --text --dismount /tmp/vc_test_mnt --non-interactive 2>/dev/null || true
        else
            echo "Validation: Failed to mount volume after restore."
        fi
    else
        echo "Validation: Restore command returned error."
        
        # Fallback attempt with piped input if strict CLI args failed
        echo -e "2\n$FILE_PATH_USED\nMountMe2024\n" | veracrypt --text --restore-headers "$TEST_VOL" --non-interactive 2>/dev/null
        
        # Retry mount
        if veracrypt --text --mount "$TEST_VOL" /tmp/vc_test_mnt \
            --password='MountMe2024' --pim=0 --keyfiles='' --protect-hidden=no --non-interactive 2>/dev/null; then
            FUNCTIONAL_RESTORE_SUCCESS="true"
            veracrypt --text --dismount /tmp/vc_test_mnt --non-interactive 2>/dev/null || true
        fi
    fi
    
    # Clean up
    rm -f "$TEST_VOL" 2>/dev/null
    rmdir /tmp/vc_test_mnt 2>/dev/null
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
# Using python for reliable JSON creation to avoid shell quoting issues
python3 -c "
import json
import os

result = {
    'file_exists': $FILE_EXISTS,
    'file_path': '$FILE_PATH_USED',
    'file_size': $FILE_SIZE,
    'file_created_during_task': $FILE_CREATED_DURING_TASK,
    'original_intact': $ORIGINAL_INTACT,
    'volume_left_mounted': $VOLUME_LEFT_MOUNTED,
    'functional_restore_success': $FUNCTIONAL_RESTORE_SUCCESS,
    'screenshot_path': '/tmp/task_final.png',
    'timestamp': '$(date -Iseconds)'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="