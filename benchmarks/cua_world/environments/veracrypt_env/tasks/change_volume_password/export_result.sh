#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Change Volume Password Result ==="

VOLUME_PATH="/home/ga/Volumes/test_volume.hc"

# Test if old password still works
OLD_PWD_WORKS="false"
mkdir -p /tmp/vc_old_test
if veracrypt --text --mount "$VOLUME_PATH" /tmp/vc_old_test \
    --password='OldPassword123' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive 2>/dev/null; then
    OLD_PWD_WORKS="true"
    veracrypt --text --dismount /tmp/vc_old_test --non-interactive 2>/dev/null || true
    sleep 1
fi
rmdir /tmp/vc_old_test 2>/dev/null || true

# Test if new password works
NEW_PWD_WORKS="false"
mkdir -p /tmp/vc_new_test
if veracrypt --text --mount "$VOLUME_PATH" /tmp/vc_new_test \
    --password='NewSecure2024' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive 2>/dev/null; then
    NEW_PWD_WORKS="true"
    veracrypt --text --dismount /tmp/vc_new_test --non-interactive 2>/dev/null || true
    sleep 1
fi
rmdir /tmp/vc_new_test 2>/dev/null || true

# Get initial state
INITIAL_OLD_PWD=$(cat /tmp/initial_old_pwd_works.txt 2>/dev/null || echo "unknown")

# Check if volume file still exists and is valid
VOLUME_EXISTS="false"
VOLUME_SIZE_BYTES=0
if [ -f "$VOLUME_PATH" ]; then
    VOLUME_EXISTS="true"
    VOLUME_SIZE_BYTES=$(stat -c%s "$VOLUME_PATH" 2>/dev/null || echo "0")
fi

# Take screenshot
take_screenshot /tmp/task_end.png

# Write result
RESULT_JSON=$(cat << EOF
{
    "volume_exists": $VOLUME_EXISTS,
    "volume_size_bytes": $VOLUME_SIZE_BYTES,
    "old_password_works": $OLD_PWD_WORKS,
    "new_password_works": $NEW_PWD_WORKS,
    "initial_old_password_worked": "$INITIAL_OLD_PWD",
    "password_changed": $([ "$NEW_PWD_WORKS" = "true" ] && [ "$OLD_PWD_WORKS" = "false" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/veracrypt_password_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/veracrypt_password_result.json"
cat /tmp/veracrypt_password_result.json

echo "=== Export Complete ==="
