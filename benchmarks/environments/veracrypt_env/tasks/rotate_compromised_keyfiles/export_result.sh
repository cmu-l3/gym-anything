#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Key Rotation Result ==="

# Configuration
VOL_PATH="/home/ga/Volumes/lab_data.hc"
OLD_KEY="/home/ga/Keyfiles/lab_access_compromised.key"
NEW_KEY="/home/ga/Keyfiles/lab_access_v2.key"
PASSWORD="Research2024!"
MOUNT_TEST_DIR="/tmp/vc_verify_mount"

# Ensure mount point exists
mkdir -p "$MOUNT_TEST_DIR"

# Dismount everything first to ensure clean state
veracrypt --text --dismount --non-interactive 2>/dev/null || true

# --- Check 1: New Keyfile Existence ---
NEW_KEY_EXISTS="false"
if [ -f "$NEW_KEY" ]; then
    NEW_KEY_EXISTS="true"
fi

# --- Check 2: In-Place Modification (Inode Check) ---
INITIAL_INODE=$(cat /tmp/initial_inode.txt 2>/dev/null || echo "0")
CURRENT_INODE=$(stat -c %i "$VOL_PATH" 2>/dev/null || echo "1")
INODE_MATCH="false"
if [ "$INITIAL_INODE" = "$CURRENT_INODE" ]; then
    INODE_MATCH="true"
fi

# --- Check 3: Mount with NEW Key (Positive Control) ---
MOUNT_NEW_SUCCESS="false"
if [ "$NEW_KEY_EXISTS" = "true" ]; then
    echo "Attempting mount with NEW key..."
    if veracrypt --text --mount "$VOL_PATH" "$MOUNT_TEST_DIR" \
        --password="$PASSWORD" \
        --keyfiles="$NEW_KEY" \
        --pim=0 \
        --protect-hidden=no \
        --non-interactive >/dev/null 2>&1; then
        
        if mountpoint -q "$MOUNT_TEST_DIR"; then
            MOUNT_NEW_SUCCESS="true"
            # Verify data is still there
            if [ -f "$MOUNT_TEST_DIR/experiment_results.csv" ]; then
                DATA_INTACT="true"
            else
                DATA_INTACT="false"
            fi
            veracrypt --text --dismount "$MOUNT_TEST_DIR" --non-interactive
        fi
    fi
fi

# --- Check 4: Mount with OLD Key (Negative Control) ---
# Should FAIL if the old key was removed
echo "Attempting mount with OLD key..."
MOUNT_OLD_SUCCESS="false"
if veracrypt --text --mount "$VOL_PATH" "$MOUNT_TEST_DIR" \
    --password="$PASSWORD" \
    --keyfiles="$OLD_KEY" \
    --pim=0 \
    --protect-hidden=no \
    --non-interactive >/dev/null 2>&1; then
    
    if mountpoint -q "$MOUNT_TEST_DIR"; then
        MOUNT_OLD_SUCCESS="true"
        veracrypt --text --dismount "$MOUNT_TEST_DIR" --non-interactive
    fi
fi

# --- Check 5: Mount with Password ONLY (Negative Control) ---
# Should FAIL (keyfile required)
echo "Attempting mount with Password ONLY..."
MOUNT_PASS_ONLY_SUCCESS="false"
if veracrypt --text --mount "$VOL_PATH" "$MOUNT_TEST_DIR" \
    --password="$PASSWORD" \
    --keyfiles="" \
    --pim=0 \
    --protect-hidden=no \
    --non-interactive >/dev/null 2>&1; then
    
    if mountpoint -q "$MOUNT_TEST_DIR"; then
        MOUNT_PASS_ONLY_SUCCESS="true"
        veracrypt --text --dismount "$MOUNT_TEST_DIR" --non-interactive
    fi
fi

# Clean up
rmdir "$MOUNT_TEST_DIR" 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "new_key_exists": $NEW_KEY_EXISTS,
    "inode_match": $INODE_MATCH,
    "mount_new_success": $MOUNT_NEW_SUCCESS,
    "mount_old_success": $MOUNT_OLD_SUCCESS,
    "mount_pass_only_success": $MOUNT_PASS_ONLY_SUCCESS,
    "data_intact": ${DATA_INTACT:-false},
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
write_result_json "/tmp/task_result.json" "$(cat $TEMP_JSON)"
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json