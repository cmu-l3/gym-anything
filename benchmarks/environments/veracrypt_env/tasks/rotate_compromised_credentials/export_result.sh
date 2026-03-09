#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Rotate Credentials Result ==="

VOLUME_PATH="/home/ga/Volumes/project_omega.hc"
OLD_KEY_BACKUP="/var/lib/veracrypt_task/backup_old.key"
NEW_KEY_PATH="/home/ga/Keyfiles/omega_v2.key"
COMPROMISED_KEY_PATH="/home/ga/Pictures/server_rack_001.jpg"

# 1. Check if files exist
[ -f "$VOLUME_PATH" ] && VOL_EXISTS="true" || VOL_EXISTS="false"
[ -f "$NEW_KEY_PATH" ] && NEW_KEY_EXISTS="true" || NEW_KEY_EXISTS="false"
[ -f "$COMPROMISED_KEY_PATH" ] && OLD_KEY_DELETED="false" || OLD_KEY_DELETED="true"

# 2. Keyfile Analysis
KEYS_ARE_DIFFERENT="false"
if [ "$NEW_KEY_EXISTS" = "true" ] && [ -f "$OLD_KEY_BACKUP" ]; then
    MD5_NEW=$(md5sum "$NEW_KEY_PATH" | awk '{print $1}')
    MD5_OLD=$(md5sum "$OLD_KEY_BACKUP" | awk '{print $1}')
    if [ "$MD5_NEW" != "$MD5_OLD" ]; then
        KEYS_ARE_DIFFERENT="true"
    fi
fi

# 3. Mount Test 1: Negative Test (Old Creds)
# Should FAIL to mount if the password/keyfile was changed correctly
NEGATIVE_TEST_PASSED="false"
mkdir -p /tmp/vc_test_neg
echo "Testing old credentials (should fail)..."
if veracrypt --text --mount "$VOLUME_PATH" /tmp/vc_test_neg \
    --password='OmegaStart2023' \
    --keyfiles="$OLD_KEY_BACKUP" \
    --pim=0 \
    --protect-hidden=no \
    --non-interactive 2>/dev/null; then
    
    echo "FAIL: Old credentials still work!"
    veracrypt --text --dismount /tmp/vc_test_neg --non-interactive 2>/dev/null || true
    NEGATIVE_TEST_PASSED="false"
else
    echo "PASS: Old credentials rejected."
    NEGATIVE_TEST_PASSED="true"
fi

# 4. Mount Test 2: Mixed Test (New Password + Old Keyfile)
# Should FAIL if the old keyfile was removed from the volume
MIXED_TEST_PASSED="false"
if [ "$NEGATIVE_TEST_PASSED" = "true" ]; then
    echo "Testing New Pass + Old Key (should fail)..."
    if veracrypt --text --mount "$VOLUME_PATH" /tmp/vc_test_neg \
        --password='Titanium#Shield2025' \
        --keyfiles="$OLD_KEY_BACKUP" \
        --pim=0 \
        --protect-hidden=no \
        --non-interactive 2>/dev/null; then
        
        echo "FAIL: Old keyfile still active!"
        veracrypt --text --dismount /tmp/vc_test_neg --non-interactive 2>/dev/null || true
        MIXED_TEST_PASSED="false"
    else
        echo "PASS: Old keyfile rejected."
        MIXED_TEST_PASSED="true"
    fi
fi
rmdir /tmp/vc_test_neg 2>/dev/null || true

# 5. Mount Test 3: Positive Test (New Creds)
# Should SUCCEED
POSITIVE_TEST_PASSED="false"
mkdir -p /tmp/vc_test_pos
if [ "$NEW_KEY_EXISTS" = "true" ]; then
    echo "Testing new credentials..."
    if veracrypt --text --mount "$VOLUME_PATH" /tmp/vc_test_pos \
        --password='Titanium#Shield2025' \
        --keyfiles="$NEW_KEY_PATH" \
        --pim=0 \
        --protect-hidden=no \
        --non-interactive 2>/dev/null; then
        
        echo "PASS: New credentials work."
        POSITIVE_TEST_PASSED="true"
        veracrypt --text --dismount /tmp/vc_test_pos --non-interactive 2>/dev/null || true
    else
        echo "FAIL: New credentials failed."
    fi
fi
rmdir /tmp/vc_test_pos 2>/dev/null || true

# 6. Check if user left it mounted (as requested)
IS_MOUNTED="false"
MOUNT_CHECK=$(veracrypt --text --list --non-interactive 2>/dev/null || echo "")
if echo "$MOUNT_CHECK" | grep -q "$VOLUME_PATH"; then
    IS_MOUNTED="true"
fi

# 7. Final Screenshot
take_screenshot /tmp/task_final.png

# 8. Write JSON
RESULT_JSON=$(cat << EOF
{
    "volume_exists": $VOL_EXISTS,
    "new_keyfile_exists": $NEW_KEY_EXISTS,
    "old_keyfile_deleted": $OLD_KEY_DELETED,
    "keys_are_different": $KEYS_ARE_DIFFERENT,
    "negative_test_passed": $NEGATIVE_TEST_PASSED,
    "mixed_test_passed": $MIXED_TEST_PASSED,
    "positive_test_passed": $POSITIVE_TEST_PASSED,
    "is_mounted_at_end": $IS_MOUNTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"
cat /tmp/task_result.json
echo "=== Export Complete ==="