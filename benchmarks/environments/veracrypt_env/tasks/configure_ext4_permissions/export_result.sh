#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Result ==="

VOLUME_PATH="/home/ga/Volumes/sysadmin_vault.hc"
MOUNT_POINT="/tmp/vc_verify_mount"
PASSWORD="SysAdmin!2024"

# Initialize result variables
VOLUME_EXISTS="false"
MOUNT_SUCCESS="false"
FS_TYPE="unknown"
SCRIPT_EXISTS="false"
SCRIPT_EXECUTABLE="false"
SCRIPT_CONTENT_MATCH="false"
DIR_EXISTS="false"
DIR_MODE="000"

# 1. Check Volume Existence
if [ -f "$VOLUME_PATH" ]; then
    VOLUME_EXISTS="true"
    echo "Volume found at $VOLUME_PATH"
else
    echo "Volume not found"
fi

# 2. Mount Volume for Inspection (Agent should have dismounted it)
if [ "$VOLUME_EXISTS" = "true" ]; then
    mkdir -p "$MOUNT_POINT"
    
    # Try to mount
    echo "Attempting to mount volume..."
    if veracrypt --text --mount "$VOLUME_PATH" "$MOUNT_POINT" \
        --password="$PASSWORD" \
        --pim=0 \
        --keyfiles="" \
        --protect-hidden=no \
        --non-interactive > /dev/null 2>&1; then
        
        MOUNT_SUCCESS="true"
        echo "Mount successful."

        # 3. Check Filesystem Type
        # df -T output example: /dev/mapper/veracrypt1   ext4   100M  ...
        FS_TYPE=$(df -T "$MOUNT_POINT" | tail -1 | awk '{print $2}')
        echo "Filesystem type: $FS_TYPE"

        # 4. Check Script
        SCRIPT_PATH="$MOUNT_POINT/deploy_fix.sh"
        if [ -f "$SCRIPT_PATH" ]; then
            SCRIPT_EXISTS="true"
            
            # Check executable bit
            if [ -x "$SCRIPT_PATH" ]; then
                SCRIPT_EXECUTABLE="true"
            fi
            
            # Check content
            if grep -q "Deploying critical fix" "$SCRIPT_PATH"; then
                SCRIPT_CONTENT_MATCH="true"
            fi
        fi

        # 5. Check Directory Permissions
        DIR_PATH="$MOUNT_POINT/ssh_keys"
        if [ -d "$DIR_PATH" ]; then
            DIR_EXISTS="true"
            # Get permissions in octal (e.g., 700)
            DIR_MODE=$(stat -c "%a" "$DIR_PATH")
            echo "Directory mode: $DIR_MODE"
        fi

        # Dismount after inspection
        veracrypt --text --dismount "$MOUNT_POINT" --non-interactive >/dev/null 2>&1 || true
    else
        echo "Failed to mount volume (wrong password or corrupted header?)"
    fi
    rmdir "$MOUNT_POINT" 2>/dev/null || true
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON Result
RESULT_JSON=$(cat << EOF
{
    "volume_exists": $VOLUME_EXISTS,
    "mount_success": $MOUNT_SUCCESS,
    "filesystem_type": "$FS_TYPE",
    "script_exists": $SCRIPT_EXISTS,
    "script_executable": $SCRIPT_EXECUTABLE,
    "script_content_match": $SCRIPT_CONTENT_MATCH,
    "dir_exists": $DIR_EXISTS,
    "dir_mode": "$DIR_MODE",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"
echo "Result exported to /tmp/task_result.json"