#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Volume with PIM Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
VOLUME_PATH="/home/ga/Volumes/pim_volume.hc"
SOURCE_CHECKSUM=$(cat /tmp/source_file_checksum.txt 2>/dev/null || echo "dummy")

# 1. Check Volume Existence & Timestamp
VOLUME_EXISTS="false"
CREATED_DURING_TASK="false"
VOLUME_SIZE_MB=0

if [ -f "$VOLUME_PATH" ]; then
    VOLUME_EXISTS="true"
    MTIME=$(stat -c %Y "$VOLUME_PATH" 2>/dev/null || echo "0")
    SIZE_BYTES=$(stat -c %s "$VOLUME_PATH" 2>/dev/null || echo "0")
    VOLUME_SIZE_MB=$((SIZE_BYTES / 1048576))
    
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Dismount State
# Agent should have dismounted the volume
IS_MOUNTED_NOW="false"
if veracrypt --text --list | grep -q "$VOLUME_PATH"; then
    IS_MOUNTED_NOW="true"
fi

# 3. Validation: Positive Mount Test (Correct Password + PIM 10)
# This verifies the volume is valid and credentials are correct
MOUNT_PIM10_SUCCESS="false"
FILE_INSIDE_FOUND="false"
FILE_CONTENT_MATCH="false"
MOUNT_POINT_TMP="/tmp/vc_check_pim10"

if [ "$VOLUME_EXISTS" = "true" ]; then
    mkdir -p "$MOUNT_POINT_TMP"
    echo "Attempting mount with PIM=10..."
    
    if veracrypt --text --mount "$VOLUME_PATH" "$MOUNT_POINT_TMP" \
        --password='StrongPIMtestPassword2024!' \
        --pim=10 \
        --keyfiles="" \
        --protect-hidden=no \
        --non-interactive > /tmp/mount_log_pos.txt 2>&1; then
        
        MOUNT_PIM10_SUCCESS="true"
        
        # Check file content
        if [ -f "$MOUNT_POINT_TMP/SF312_Nondisclosure_Agreement.txt" ]; then
            FILE_INSIDE_FOUND="true"
            ACTUAL_SUM=$(sha256sum "$MOUNT_POINT_TMP/SF312_Nondisclosure_Agreement.txt" | awk '{print $1}')
            if [ "$ACTUAL_SUM" == "$SOURCE_CHECKSUM" ]; then
                FILE_CONTENT_MATCH="true"
            fi
        fi
        
        # Cleanup
        veracrypt --text --dismount "$MOUNT_POINT_TMP" --non-interactive 2>/dev/null || true
    else
        echo "Mount with PIM=10 failed."
        cat /tmp/mount_log_pos.txt
    fi
    rmdir "$MOUNT_POINT_TMP" 2>/dev/null || true
fi

# 4. Validation: Negative Mount Test (Correct Password + PIM 0/Default)
# This verifies that PIM was ACTUALLY set. If this succeeds, the agent failed to set PIM.
MOUNT_DEFAULT_SUCCESS="false"
MOUNT_POINT_TMP_NEG="/tmp/vc_check_pim0"

if [ "$VOLUME_EXISTS" = "true" ]; then
    mkdir -p "$MOUNT_POINT_TMP_NEG"
    echo "Attempting mount with Default PIM (checking for anti-gaming)..."
    
    # Try mounting without specifying PIM (or PIM=0)
    if veracrypt --text --mount "$VOLUME_PATH" "$MOUNT_POINT_TMP_NEG" \
        --password='StrongPIMtestPassword2024!' \
        --pim=0 \
        --keyfiles="" \
        --protect-hidden=no \
        --non-interactive > /tmp/mount_log_neg.txt 2>&1; then
        
        MOUNT_DEFAULT_SUCCESS="true"
        # We don't want this to succeed!
        veracrypt --text --dismount "$MOUNT_POINT_TMP_NEG" --non-interactive 2>/dev/null || true
    fi
    rmdir "$MOUNT_POINT_TMP_NEG" 2>/dev/null || true
fi

# 5. Capture Evidence
take_screenshot /tmp/task_final.png

# 6. JSON Export
RESULT_JSON=$(cat << EOF
{
    "volume_exists": $VOLUME_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "volume_size_mb": $VOLUME_SIZE_MB,
    "final_is_mounted": $IS_MOUNTED_NOW,
    "mount_pim10_success": $MOUNT_PIM10_SUCCESS,
    "mount_default_success": $MOUNT_DEFAULT_SUCCESS,
    "file_inside_found": $FILE_INSIDE_FOUND,
    "file_content_match": $FILE_CONTENT_MATCH,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="