#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Secure Visual Migration Result ==="

# Load Answer Key
if [ -f /var/lib/veracrypt_task/answers.env ]; then
    source /var/lib/veracrypt_task/answers.env
else
    echo "ERROR: Answer key not found!"
    SOURCE_KEY_PATH=""
    DEST_KEY_PATH=""
fi

NEW_VOLUME="/home/ga/Volumes/new_storage.hc"
MOUNT_POINT="/tmp/vc_verify_new"

# Initialize Result Variables
VOL_EXISTS="false"
MOUNT_SUCCESS="false"
PIM_VERIFIED="false"
FILES_TRANSFERRED="false"
FILE_COUNT=0
CORRECT_KEYFILE_USED="false"

# 1. Check Volume Existence
if [ -f "$NEW_VOLUME" ]; then
    VOL_EXISTS="true"
    echo "New volume found."
fi

# 2. Verify Volume Security (Mount with specific params)
# We specifically use the DEST_KEY_PATH (Mountain) and PIM 485.
# If this succeeds, the agent correctly identified the image and set the PIM.

if [ "$VOL_EXISTS" = "true" ]; then
    mkdir -p "$MOUNT_POINT"
    
    echo "Attempting to mount with expected credentials..."
    echo "Keyfile: $DEST_KEY_PATH"
    echo "PIM: 485"
    
    # Try mount
    veracrypt --text --mount "$NEW_VOLUME" "$MOUNT_POINT" \
        --password='Migrated#Secure99' \
        --keyfiles="$DEST_KEY_PATH" \
        --pim=485 \
        --protect-hidden=no \
        --non-interactive > /tmp/mount_log.txt 2>&1
        
    MOUNT_EXIT_CODE=$?
    
    if [ $MOUNT_EXIT_CODE -eq 0 ] && mountpoint -q "$MOUNT_POINT"; then
        MOUNT_SUCCESS="true"
        PIM_VERIFIED="true" # If mount worked with PIM 485, PIM is correct
        CORRECT_KEYFILE_USED="true" # If mount worked with keyfile, keyfile is correct
        
        # 3. Check Data Integrity
        echo "Checking files in new volume..."
        REQUIRED_FILES=("SF312_Nondisclosure_Agreement.txt" "FY2024_Revenue_Budget.csv" "backup_authorized_keys")
        MISSING_FILES=0
        
        for file in "${REQUIRED_FILES[@]}"; do
            if [ -f "$MOUNT_POINT/$file" ]; then
                echo "Found: $file"
            else
                echo "Missing: $file"
                MISSING_FILES=$((MISSING_FILES + 1))
            fi
        done
        
        FILE_COUNT=$(ls -1 "$MOUNT_POINT" | wc -l)
        
        if [ $MISSING_FILES -eq 0 ]; then
            FILES_TRANSFERRED="true"
        fi
        
        # Dismount
        veracrypt --text --dismount "$MOUNT_POINT" --non-interactive
    else
        echo "Mount failed. Log:"
        cat /tmp/mount_log.txt
        
        # Diagnostic: Did they forget PIM? Try mounting with PIM=0 to see if they failed that part
        echo "Diagnostic: Trying mount with PIM=0..."
        veracrypt --text --mount "$NEW_VOLUME" "$MOUNT_POINT" \
            --password='Migrated#Secure99' \
            --keyfiles="$DEST_KEY_PATH" \
            --pim=0 \
            --protect-hidden=no \
            --non-interactive > /dev/null 2>&1
            
        if mountpoint -q "$MOUNT_POINT"; then
            echo "Mount succeeded with PIM=0 (Agent forgot PIM)"
            MOUNT_SUCCESS="true"
            PIM_VERIFIED="false"
            CORRECT_KEYFILE_USED="true"
            veracrypt --text --dismount "$MOUNT_POINT" --non-interactive
        fi
    fi
    rmdir "$MOUNT_POINT" 2>/dev/null || true
fi

# 4. Check Cleanup (No volumes should be mounted)
MOUNT_LIST=$(veracrypt --text --list --non-interactive 2>&1 || echo "")
CLEANUP_DONE="false"
if ! echo "$MOUNT_LIST" | grep -q "^[0-9]"; then
    CLEANUP_DONE="true"
fi

# 5. Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Export JSON
RESULT_JSON=$(cat << EOF
{
    "volume_exists": $VOL_EXISTS,
    "mount_success": $MOUNT_SUCCESS,
    "pim_correct": $PIM_VERIFIED,
    "keyfile_correct": $CORRECT_KEYFILE_USED,
    "files_transferred": $FILES_TRANSFERRED,
    "file_count": $FILE_COUNT,
    "cleanup_done": $CLEANUP_DONE,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"
cat /tmp/task_result.json

echo "=== Export Complete ==="