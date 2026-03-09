#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting create_hidden_volume result ==="

# Define paths and passwords
VOLUME_PATH="/home/ga/Volumes/plausible_deniability.hc"
OUTER_PASS="CoverStory2024"
HIDDEN_PASS="RealSecret!789"
OUTER_MOUNT="/tmp/verify_outer"
HIDDEN_MOUNT="/tmp/verify_hidden"

# Get timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
FILE_EXISTS="false"
FILE_SIZE_BYTES=0
OUTER_MOUNTABLE="false"
DECOY_FILES_PRESENT="false"
DECOY_FILES_FOUND=""
HIDDEN_MOUNTABLE="false"
FILESYSTEMS_DISTINCT="false"
OUTER_UUID=""
HIDDEN_UUID=""
IS_COPY="false"
TIMESTAMP_VALID="false"

# 1. Check File Existence and Size
if [ -f "$VOLUME_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c%s "$VOLUME_PATH")
    
    # Check creation timestamp
    FILE_MTIME=$(stat -c%Y "$VOLUME_PATH")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        TIMESTAMP_VALID="true"
    fi
    
    # Check if it's a copy of a pre-existing volume (anti-gaming)
    CURRENT_HASH=$(sha256sum "$VOLUME_PATH" | awk '{print $1}')
    if grep -q "$CURRENT_HASH" /tmp/pre_existing_volume_hashes.txt 2>/dev/null; then
        IS_COPY="true"
    fi
fi

# Ensure everything is dismounted before verification
veracrypt --text --dismount --non-interactive 2>/dev/null || true
mkdir -p "$OUTER_MOUNT" "$HIDDEN_MOUNT"

# 2. Verify Outer Volume (Decoy)
if [ "$FILE_EXISTS" = "true" ]; then
    echo "Verifying Outer Volume..."
    if veracrypt --text --mount "$VOLUME_PATH" "$OUTER_MOUNT" \
        --password="$OUTER_PASS" --pim=0 --keyfiles="" --protect-hidden=no --non-interactive >/dev/null 2>&1; then
        
        OUTER_MOUNTABLE="true"
        
        # Check for decoy files
        if [ -f "$OUTER_MOUNT/SF312_Nondisclosure_Agreement.txt" ] && \
           [ -f "$OUTER_MOUNT/FY2024_Revenue_Budget.csv" ]; then
            DECOY_FILES_PRESENT="true"
            DECOY_FILES_FOUND=$(ls "$OUTER_MOUNT" | tr '\n' ',')
        fi
        
        # Get UUID
        OUTER_UUID=$(blkid -o value -s UUID $(mount | grep "$OUTER_MOUNT" | awk '{print $1}') 2>/dev/null || echo "uuid_outer")
        
        # Dismount
        veracrypt --text --dismount "$OUTER_MOUNT" --non-interactive
    fi
fi

# 3. Verify Hidden Volume
if [ "$FILE_EXISTS" = "true" ]; then
    echo "Verifying Hidden Volume..."
    if veracrypt --text --mount "$VOLUME_PATH" "$HIDDEN_MOUNT" \
        --password="$HIDDEN_PASS" --pim=0 --keyfiles="" --protect-hidden=no --non-interactive >/dev/null 2>&1; then
        
        HIDDEN_MOUNTABLE="true"
        
        # Get UUID
        HIDDEN_UUID=$(blkid -o value -s UUID $(mount | grep "$HIDDEN_MOUNT" | awk '{print $1}') 2>/dev/null || echo "uuid_hidden")
        
        # Dismount
        veracrypt --text --dismount "$HIDDEN_MOUNT" --non-interactive
    fi
fi

# 4. Check if filesystems are distinct
if [ "$OUTER_MOUNTABLE" = "true" ] && [ "$HIDDEN_MOUNTABLE" = "true" ]; then
    if [ "$OUTER_UUID" != "$HIDDEN_UUID" ]; then
        FILESYSTEMS_DISTINCT="true"
    fi
fi

# Clean up
rmdir "$OUTER_MOUNT" "$HIDDEN_MOUNT" 2>/dev/null || true

# Construct JSON result
# Using python to safely construct JSON to handle potential escaping issues
cat << EOF > /tmp/task_result.json
{
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE_BYTES,
    "timestamp_valid": $TIMESTAMP_VALID,
    "is_copy": $IS_COPY,
    "outer_mountable": $OUTER_MOUNTABLE,
    "decoy_files_present": $DECOY_FILES_PRESENT,
    "hidden_mountable": $HIDDEN_MOUNTABLE,
    "filesystems_distinct": $FILESYSTEMS_DISTINCT,
    "decoy_files_found": "$DECOY_FILES_FOUND",
    "outer_uuid": "$OUTER_UUID",
    "hidden_uuid": "$HIDDEN_UUID",
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
EOF

# Ensure readable
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="