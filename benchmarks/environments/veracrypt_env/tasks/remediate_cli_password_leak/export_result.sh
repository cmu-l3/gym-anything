#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Remediate CLI Password Leak Result ==="

VOLUME_PATH="/home/ga/Volumes/internal_ops.hc"
HISTORY_FILE="/home/ga/.bash_history"
TARGET_PASSWORD="SecuredCredential2025!"
LEAKED_PASSWORD=$(cat /tmp/original_leaked_password.txt 2>/dev/null || echo "")

# 1. Test: Does the NEW password work?
NEW_PASS_WORKS="false"
mkdir -p /tmp/vc_test_new
if veracrypt --text --mount "$VOLUME_PATH" /tmp/vc_test_new \
    --password="$TARGET_PASSWORD" \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive >/dev/null 2>&1; then
    NEW_PASS_WORKS="true"
    veracrypt --text --dismount /tmp/vc_test_new --non-interactive >/dev/null 2>&1 || true
fi
rmdir /tmp/vc_test_new 2>/dev/null || true

# 2. Test: Does the OLD (leaked) password still work?
OLD_PASS_WORKS="false"
if [ -n "$LEAKED_PASSWORD" ]; then
    mkdir -p /tmp/vc_test_old
    if veracrypt --text --mount "$VOLUME_PATH" /tmp/vc_test_old \
        --password="$LEAKED_PASSWORD" \
        --pim=0 \
        --keyfiles="" \
        --protect-hidden=no \
        --non-interactive >/dev/null 2>&1; then
        OLD_PASS_WORKS="true"
        veracrypt --text --dismount /tmp/vc_test_old --non-interactive >/dev/null 2>&1 || true
    fi
    rmdir /tmp/vc_test_old 2>/dev/null || true
fi

# 3. Test: Is the leak removed from history?
HISTORY_SANITIZED="false"
LEAK_FOUND_IN_HISTORY="false"

if [ -f "$HISTORY_FILE" ]; then
    if grep -Fq "$LEAKED_PASSWORD" "$HISTORY_FILE"; then
        LEAK_FOUND_IN_HISTORY="true"
        HISTORY_SANITIZED="false"
    else
        LEAK_FOUND_IN_HISTORY="false"
        HISTORY_SANITIZED="true"
    fi
else
    # If history file was deleted entirely, that's one way to sanitize, though drastic.
    # We'll count it as sanitized but note it.
    HISTORY_SANITIZED="true"
    LEAK_FOUND_IN_HISTORY="false"
fi

# 4. Check if app was running
APP_RUNNING="false"
if is_veracrypt_running; then
    APP_RUNNING="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
RESULT_JSON=$(cat << EOF
{
    "new_password_works": $NEW_PASS_WORKS,
    "old_password_works": $OLD_PASS_WORKS,
    "history_sanitized": $HISTORY_SANITIZED,
    "leak_found_in_history": $LEAK_FOUND_IN_HISTORY,
    "leaked_password_was": "$LEAKED_PASSWORD",
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="