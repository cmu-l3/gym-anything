#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Organize Encrypted Workspace Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
VOLUME_PATH="/home/ga/Volumes/data_volume.hc"
VERIFY_MOUNT="/tmp/vc_verify_mount"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
VOLUME_DISMOUNTED="false"
FILESYSTEM_TYPE="unknown"
STRUCTURE_VALID="false"
FILES_MOVED="false"
ROOT_CLEAN="false"
PERMS_VALID="false"
MANIFEST_EXISTS="false"
MANIFEST_VALID="false"
MANIFEST_COUNT=0

# 1. Check if currently dismounted (Step 1 of verification)
MOUNT_LIST=$(veracrypt --text --list --non-interactive 2>&1 || echo "")
if echo "$MOUNT_LIST" | grep -q "data_volume"; then
    VOLUME_DISMOUNTED="false"
    echo "Volume is still mounted."
else
    VOLUME_DISMOUNTED="true"
    echo "Volume is dismounted."
fi

# 2. Re-mount for verification
mkdir -p "$VERIFY_MOUNT"
echo "Mounting for verification..."
# Try to mount (agent may have changed pwd, but task says keep password 'MountMe2024')
if veracrypt --text --mount "$VOLUME_PATH" "$VERIFY_MOUNT" \
    --password='MountMe2024' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive 2>/dev/null; then
    
    echo "Mount successful."
    
    # Check Filesystem Type
    FILESYSTEM_TYPE=$(df -T "$VERIFY_MOUNT" | tail -1 | awk '{print $2}')
    echo "Filesystem: $FILESYSTEM_TYPE"

    # Check Directory Structure
    if [ -d "$VERIFY_MOUNT/legal" ] && \
       [ -d "$VERIFY_MOUNT/financial" ] && \
       [ -d "$VERIFY_MOUNT/credentials" ]; then
        STRUCTURE_VALID="true"
    fi

    # Check File Locations
    if [ -f "$VERIFY_MOUNT/legal/SF312_Nondisclosure_Agreement.txt" ] && \
       [ -f "$VERIFY_MOUNT/financial/FY2024_Revenue_Budget.csv" ] && \
       [ -f "$VERIFY_MOUNT/credentials/backup_authorized_keys" ]; then
        FILES_MOVED="true"
    fi

    # Check Root Cleanliness
    if [ ! -f "$VERIFY_MOUNT/SF312_Nondisclosure_Agreement.txt" ] && \
       [ ! -f "$VERIFY_MOUNT/FY2024_Revenue_Budget.csv" ] && \
       [ ! -f "$VERIFY_MOUNT/backup_authorized_keys" ]; then
        ROOT_CLEAN="true"
    fi

    # Check Permissions (Only valid if filesystem supports it, e.g., ext4)
    # Target: credentials=700, keys=600
    CRED_PERM=$(stat -c "%a" "$VERIFY_MOUNT/credentials" 2>/dev/null || echo "000")
    KEY_PERM=$(stat -c "%a" "$VERIFY_MOUNT/credentials/backup_authorized_keys" 2>/dev/null || echo "000")
    
    echo "Permissions - Creds: $CRED_PERM, Key: $KEY_PERM"
    
    if [ "$CRED_PERM" = "700" ] && [ "$KEY_PERM" = "600" ]; then
        PERMS_VALID="true"
    fi

    # Check Manifest
    if [ -f "$VERIFY_MOUNT/manifest.sha256" ]; then
        MANIFEST_EXISTS="true"
        MANIFEST_COUNT=$(wc -l < "$VERIFY_MOUNT/manifest.sha256")
        
        # Validate checksums
        cd "$VERIFY_MOUNT"
        if sha256sum --status -c manifest.sha256 2>/dev/null; then
            MANIFEST_VALID="true"
        else
             # Try ignoring missing files if pathing is weird, just to see if lines match
             if sha256sum -c manifest.sha256 2>/dev/null | grep -q "OK"; then
                 # Partial match? strict check failed though
                 MANIFEST_VALID="false" 
             fi
        fi
        cd - > /dev/null
    fi

    # Dismount verification mount
    veracrypt --text --dismount "$VERIFY_MOUNT" --non-interactive 2>/dev/null || true
else
    echo "Failed to mount volume for verification."
fi

rmdir "$VERIFY_MOUNT" 2>/dev/null || true

# Generate JSON
RESULT_JSON=$(cat << EOF
{
    "volume_dismounted": $VOLUME_DISMOUNTED,
    "filesystem_type": "$FILESYSTEM_TYPE",
    "structure_valid": $STRUCTURE_VALID,
    "files_moved": $FILES_MOVED,
    "root_clean": $ROOT_CLEAN,
    "permissions_valid": $PERMS_VALID,
    "manifest_exists": $MANIFEST_EXISTS,
    "manifest_valid": $MANIFEST_VALID,
    "manifest_entry_count": $MANIFEST_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="