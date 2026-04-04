#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Add Keyfile Auth Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
KEYFILE="/home/ga/Keyfiles/security_audit.key"
VOLUME_PATH="/home/ga/Volumes/data_volume.hc"
LISTING_FILE="/home/ga/Documents/volume_contents.txt"

# --- 1. Check Keyfile ---
KEYFILE_EXISTS="false"
KEYFILE_SIZE=0
KEYFILE_VALID_TIME="false"

if [ -f "$KEYFILE" ]; then
    KEYFILE_EXISTS="true"
    KEYFILE_SIZE=$(stat --format='%s' "$KEYFILE" 2>/dev/null || echo "0")
    KEYFILE_MTIME=$(stat --format='%Y' "$KEYFILE" 2>/dev/null || echo "0")
    if [ "$KEYFILE_MTIME" -ge "$TASK_START" ]; then
        KEYFILE_VALID_TIME="true"
    fi
fi

# --- 2. Check Agent's Final Mount State & Data ---
MOUNTED_AT_END="false"
DATA_INTACT="false"
FILES_FOUND=0

# Check if mounted at specifically the requested slot/path or anywhere
MOUNT_CHECK=$(veracrypt --text --list 2>/dev/null | grep "$VOLUME_PATH")
if [ -n "$MOUNT_CHECK" ]; then
    MOUNTED_AT_END="true"
    
    # Find where it is mounted to check files
    MOUNT_POINT=$(echo "$MOUNT_CHECK" | awk '{print $3}')
    if [ -d "$MOUNT_POINT" ]; then
        if [ -f "$MOUNT_POINT/SF312_Nondisclosure_Agreement.txt" ] && \
           [ -f "$MOUNT_POINT/FY2024_Revenue_Budget.csv" ] && \
           [ -f "$MOUNT_POINT/backup_authorized_keys" ]; then
            DATA_INTACT="true"
            FILES_FOUND=3
        else
            FILES_FOUND=$(ls -1 "$MOUNT_POINT" | wc -l)
        fi
    fi
fi

# --- 3. Check Listing File ---
LISTING_EXISTS="false"
LISTING_CONTENT_MATCH="false"
if [ -f "$LISTING_FILE" ]; then
    LISTING_EXISTS="true"
    if grep -q "SF312" "$LISTING_FILE" && grep -q "Budget" "$LISTING_FILE"; then
        LISTING_CONTENT_MATCH="true"
    fi
fi

# --- 4. CRITICAL: Test Authentication Configuration ---
# To verify the task, we must ensure:
# A) Password ONLY fails (Keyfile is required)
# B) Password + Keyfile succeeds

echo "Testing authentication configuration..."

# First, force dismount everything to run tests
veracrypt --text --dismount --non-interactive 2>/dev/null || true
sleep 1

# TEST A: Password Only (Should FAIL)
TEST_PWD_ONLY_RESULT="fail" # Default to fail (which is good/pass for this check)
mkdir -p /tmp/vc_test_pwd
if veracrypt --text --mount "$VOLUME_PATH" /tmp/vc_test_pwd \
    --password='MountMe2024' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive 2>/dev/null; then
    
    # It mounted with password only -> Task Failed
    TEST_PWD_ONLY_RESULT="mounted_unexpectedly"
    veracrypt --text --dismount /tmp/vc_test_pwd --non-interactive 2>/dev/null || true
else
    # It failed to mount -> Task requirement met (Keyfile is enforced)
    TEST_PWD_ONLY_RESULT="access_denied_correctly"
fi
rmdir /tmp/vc_test_pwd 2>/dev/null || true

# TEST B: Password + Keyfile (Should SUCCEED)
TEST_FULL_AUTH_RESULT="fail"
mkdir -p /tmp/vc_test_full
if [ "$KEYFILE_EXISTS" = "true" ]; then
    if veracrypt --text --mount "$VOLUME_PATH" /tmp/vc_test_full \
        --password='MountMe2024' \
        --pim=0 \
        --keyfiles="$KEYFILE" \
        --protect-hidden=no \
        --non-interactive 2>/dev/null; then
        
        TEST_FULL_AUTH_RESULT="success"
        
        # Double check data integrity here too
        if [ -f "/tmp/vc_test_full/SF312_Nondisclosure_Agreement.txt" ]; then
             DATA_REVERIFIED="true"
        fi
        
        veracrypt --text --dismount /tmp/vc_test_full --non-interactive 2>/dev/null || true
    fi
fi
rmdir /tmp/vc_test_full 2>/dev/null || true

# --- 5. Export JSON ---
take_screenshot /tmp/task_final.png

RESULT_JSON=$(cat << EOF
{
    "keyfile_exists": $KEYFILE_EXISTS,
    "keyfile_size_bytes": $KEYFILE_SIZE,
    "keyfile_created_during_task": $KEYFILE_VALID_TIME,
    "volume_mounted_at_end": $MOUNTED_AT_END,
    "data_files_found_count": $FILES_FOUND,
    "data_intact": $DATA_INTACT,
    "listing_file_exists": $LISTING_EXISTS,
    "listing_content_match": $LISTING_CONTENT_MATCH,
    "auth_test_password_only": "$TEST_PWD_ONLY_RESULT",
    "auth_test_full_creds": "$TEST_FULL_AUTH_RESULT",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"
cat /tmp/task_result.json
echo "=== Export Complete ==="