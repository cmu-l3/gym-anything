#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Shared Custody Volume Result ==="

VOLUME_PATH="/home/ga/Volumes/root_ca_storage.hc"
TOKEN_DIR="/home/ga/Documents/OfficerTokens"
KEYFILE_ORDER="$TOKEN_DIR/CEO_Token_Keys.pub,$TOKEN_DIR/CFO_Token_Budget.csv,$TOKEN_DIR/Legal_Token_NDA.txt"
PASSWORD="TripartiteControl2026!"

# Initialize result variables
VOLUME_EXISTS="false"
VOLUME_SIZE=0
MOUNT_PASSWORD_ONLY_RESULT="failed" # Should fail
MOUNT_CORRECT_KEYS_RESULT="failed"  # Should succeed
MOUNT_WRONG_ORDER_RESULT="failed"   # Should fail (verifies order enforcement)

# 1. Check File Existence
if [ -f "$VOLUME_PATH" ]; then
    VOLUME_EXISTS="true"
    VOLUME_SIZE=$(stat -c%s "$VOLUME_PATH" 2>/dev/null || echo "0")
fi

# 2. Test Mount: Password Only (Should FAIL)
echo "Testing mount: Password Only..."
mkdir -p /tmp/vc_test_pwd
if veracrypt --text --mount "$VOLUME_PATH" /tmp/vc_test_pwd \
    --password="$PASSWORD" \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive 2>/dev/null; then
    MOUNT_PASSWORD_ONLY_RESULT="success"
    veracrypt --text --dismount /tmp/vc_test_pwd --non-interactive 2>/dev/null || true
else
    MOUNT_PASSWORD_ONLY_RESULT="failed"
fi
rmdir /tmp/vc_test_pwd 2>/dev/null || true

# 3. Test Mount: Password + Correct Keyfile Order (Should SUCCEED)
echo "Testing mount: Correct Order..."
mkdir -p /tmp/vc_test_correct
if veracrypt --text --mount "$VOLUME_PATH" /tmp/vc_test_correct \
    --password="$PASSWORD" \
    --pim=0 \
    --keyfiles="$KEYFILE_ORDER" \
    --protect-hidden=no \
    --non-interactive 2>/dev/null; then
    MOUNT_CORRECT_KEYS_RESULT="success"
    veracrypt --text --dismount /tmp/vc_test_correct --non-interactive 2>/dev/null || true
else
    MOUNT_CORRECT_KEYS_RESULT="failed"
fi
rmdir /tmp/vc_test_correct 2>/dev/null || true

# 4. Test Mount: Password + WRONG Order (Should FAIL)
# Trying: Legal -> CFO -> CEO
WRONG_ORDER="$TOKEN_DIR/Legal_Token_NDA.txt,$TOKEN_DIR/CFO_Token_Budget.csv,$TOKEN_DIR/CEO_Token_Keys.pub"
echo "Testing mount: Wrong Order..."
mkdir -p /tmp/vc_test_wrong
if veracrypt --text --mount "$VOLUME_PATH" /tmp/vc_test_wrong \
    --password="$PASSWORD" \
    --pim=0 \
    --keyfiles="$WRONG_ORDER" \
    --protect-hidden=no \
    --non-interactive 2>/dev/null; then
    MOUNT_WRONG_ORDER_RESULT="success"
    veracrypt --text --dismount /tmp/vc_test_wrong --non-interactive 2>/dev/null || true
else
    MOUNT_WRONG_ORDER_RESULT="failed"
fi
rmdir /tmp/vc_test_wrong 2>/dev/null || true

# 5. Capture Final State
take_screenshot /tmp/task_final.png

# 6. JSON Export
RESULT_JSON=$(cat << EOF
{
    "volume_exists": $VOLUME_EXISTS,
    "volume_size_bytes": $VOLUME_SIZE,
    "mount_password_only": "$MOUNT_PASSWORD_ONLY_RESULT",
    "mount_correct_keys": "$MOUNT_CORRECT_KEYS_RESULT",
    "mount_wrong_order": "$MOUNT_WRONG_ORDER_RESULT",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="