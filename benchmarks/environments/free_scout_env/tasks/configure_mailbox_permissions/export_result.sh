#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting configure_mailbox_permissions result ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load saved IDs
MAILBOX_ID=$(cat /tmp/task_mailbox_id.txt 2>/dev/null || echo "")
SARAH_ID=$(cat /tmp/task_sarah_id.txt 2>/dev/null || echo "")
MARCUS_ID=$(cat /tmp/task_marcus_id.txt 2>/dev/null || echo "")

# Load initial state
INITIAL_SARAH_ACCESS="0"
INITIAL_MARCUS_ACCESS="0"
if [ -f /tmp/initial_state.json ]; then
    INITIAL_SARAH_ACCESS=$(grep -oP '"sarah_access": \K[0-9]+' /tmp/initial_state.json || echo "0")
    INITIAL_MARCUS_ACCESS=$(grep -oP '"marcus_access": \K[0-9]+' /tmp/initial_state.json || echo "0")
fi

# Check current access
CURRENT_SARAH_ACCESS="0"
CURRENT_MARCUS_ACCESS="0"
MAILBOX_EXISTS="false"
SARAH_EXISTS="false"
MARCUS_EXISTS="false"

if [ -n "$MAILBOX_ID" ] && [ -n "$SARAH_ID" ] && [ -n "$MARCUS_ID" ]; then
    # Verify entities still exist
    MB_CHECK=$(fs_query "SELECT COUNT(*) FROM mailboxes WHERE id = $MAILBOX_ID" 2>/dev/null || echo "0")
    if [ "$MB_CHECK" -gt 0 ]; then MAILBOX_EXISTS="true"; fi
    
    SARAH_CHECK=$(fs_query "SELECT COUNT(*) FROM users WHERE id = $SARAH_ID" 2>/dev/null || echo "0")
    if [ "$SARAH_CHECK" -gt 0 ]; then SARAH_EXISTS="true"; fi

    MARCUS_CHECK=$(fs_query "SELECT COUNT(*) FROM users WHERE id = $MARCUS_ID" 2>/dev/null || echo "0")
    if [ "$MARCUS_CHECK" -gt 0 ]; then MARCUS_EXISTS="true"; fi

    # Check permissions
    CURRENT_SARAH_ACCESS=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE mailbox_id = $MAILBOX_ID AND user_id = $SARAH_ID" 2>/dev/null || echo "0")
    CURRENT_MARCUS_ACCESS=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE mailbox_id = $MAILBOX_ID AND user_id = $MARCUS_ID" 2>/dev/null || echo "0")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "mailbox_id": "${MAILBOX_ID}",
    "sarah_id": "${SARAH_ID}",
    "marcus_id": "${MARCUS_ID}",
    "mailbox_exists": ${MAILBOX_EXISTS},
    "sarah_exists": ${SARAH_EXISTS},
    "marcus_exists": ${MARCUS_EXISTS},
    "initial_sarah_access": ${INITIAL_SARAH_ACCESS},
    "initial_marcus_access": ${INITIAL_MARCUS_ACCESS},
    "current_sarah_access": ${CURRENT_SARAH_ACCESS},
    "current_marcus_access": ${CURRENT_MARCUS_ACCESS},
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="