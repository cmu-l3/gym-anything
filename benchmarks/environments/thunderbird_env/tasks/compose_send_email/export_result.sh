#!/bin/bash
echo "=== Exporting compose_send_email result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/thunderbird_final.png

# ============================================================
# Check Drafts folder for new messages
# ============================================================
INITIAL_DRAFTS=$(cat /tmp/initial_drafts_count 2>/dev/null || echo "0")
CURRENT_DRAFTS=$(count_emails_in_mbox "${LOCAL_MAIL_DIR}/Drafts")

# Check if a new draft was saved
DRAFT_ADDED="false"
DRAFT_RECIPIENT=""
DRAFT_SUBJECT=""
DRAFT_BODY=""

if [ "$CURRENT_DRAFTS" -gt "$INITIAL_DRAFTS" ]; then
    DRAFT_ADDED="true"

    # Extract the last message from the Drafts mbox
    # Reset msg on each "From " separator so only the last message remains at END
    LAST_MSG=$(awk '/^From /{msg=""} {msg=msg $0 "\n"} END{printf "%s", msg}' "${LOCAL_MAIL_DIR}/Drafts" 2>/dev/null)

    if [ -n "$LAST_MSG" ]; then
        DRAFT_RECIPIENT=$(echo "$LAST_MSG" | grep -m1 "^To:" | sed 's/^To:\s*//' | tr -d '\r')
        DRAFT_SUBJECT=$(echo "$LAST_MSG" | grep -m1 "^Subject:" | sed 's/^Subject:\s*//' | tr -d '\r')
        # Get body (after empty line separating headers from body)
        DRAFT_BODY=$(echo "$LAST_MSG" | sed -n '/^$/,$ p' | tail -n +2 | head -20 | tr '\n' ' ' | tr -d '\r')
    fi
fi

# Also check the Sent and Outbox folders as fallback
SENT_COUNT=$(count_emails_in_mbox "${LOCAL_MAIL_DIR}/Sent")
OUTBOX_EXISTS="false"
OUTBOX_COUNT=0
if [ -f "${LOCAL_MAIL_DIR}/Unsent Messages" ]; then
    OUTBOX_EXISTS="true"
    OUTBOX_COUNT=$(count_emails_in_mbox "${LOCAL_MAIL_DIR}/Unsent Messages")
fi

# Check if compose window was opened (window detection)
COMPOSE_WINDOW_OPENED="false"
if has_compose_window; then
    COMPOSE_WINDOW_OPENED="true"
fi

# Check Thunderbird is still running
TB_RUNNING="false"
if is_thunderbird_running; then
    TB_RUNNING="true"
fi

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Escape special characters for JSON (strip only outer quotes from json.dumps output)
DRAFT_SUBJECT_ESC=$(echo "$DRAFT_SUBJECT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])" 2>/dev/null || echo "$DRAFT_SUBJECT")
DRAFT_RECIPIENT_ESC=$(echo "$DRAFT_RECIPIENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])" 2>/dev/null || echo "$DRAFT_RECIPIENT")
DRAFT_BODY_ESC=$(echo "$DRAFT_BODY" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])" 2>/dev/null || echo "$DRAFT_BODY")

cat > "$TEMP_JSON" << EOF
{
    "draft_added": $DRAFT_ADDED,
    "initial_drafts_count": $INITIAL_DRAFTS,
    "current_drafts_count": $CURRENT_DRAFTS,
    "draft_recipient": "$DRAFT_RECIPIENT_ESC",
    "draft_subject": "$DRAFT_SUBJECT_ESC",
    "draft_body_snippet": "$DRAFT_BODY_ESC",
    "sent_count": $SENT_COUNT,
    "outbox_exists": $OUTBOX_EXISTS,
    "outbox_count": $OUTBOX_COUNT,
    "compose_window_opened": $COMPOSE_WINDOW_OPENED,
    "thunderbird_running": $TB_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="
