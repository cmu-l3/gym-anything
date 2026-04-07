#!/bin/bash
echo "=== Exporting remediate_malicious_filters result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot BEFORE closing
take_screenshot /tmp/task_final.png

# Gracefully close Thunderbird to flush memory/journal buffers to mbox files
close_thunderbird
sleep 3
# Force kill if it's stubbornly hanging
if is_thunderbird_running; then
    pkill -f thunderbird
    sleep 2
fi

TB_PROFILE="/home/ga/.thunderbird/default-release"
LOCAL_MAIL_DIR="$TB_PROFILE/Mail/Local Folders"
FILTER_FILE="$LOCAL_MAIL_DIR/msgFilterRules.dat"

# Check filters directly
SYSTEM_SYNC_EXISTS="false"
NEWSLETTER_EXISTS="false"
if [ -f "$FILTER_FILE" ]; then
    if grep -q 'name="System Sync"' "$FILTER_FILE"; then
        SYSTEM_SYNC_EXISTS="true"
    fi
    if grep -q 'name="Sort Newsletters"' "$FILTER_FILE"; then
        NEWSLETTER_EXISTS="true"
    fi
fi

# Use Python mailbox to safely read active (non-deleted) emails
# Thunderbird appends moved emails to the target mbox, but marks the origin as deleted via X-Mozilla-Status
cat > /tmp/check_mbox.py << 'EOF'
import mailbox
import json

def count_active(mbox_path, keyword):
    count = 0
    try:
        mbox = mailbox.mbox(mbox_path)
        for msg in mbox:
            # Check X-Mozilla-Status (0x0008 = deleted/expunged)
            status = msg.get('X-Mozilla-Status', '0000')
            try:
                if int(status, 16) & 0x0008:
                    continue  # Skip deleted emails
            except ValueError:
                pass
            
            subject = msg.get('Subject', '')
            if keyword.lower() in subject.lower():
                count += 1
    except Exception:
        pass
    return count

inbox_invoices = count_active('/home/ga/.thunderbird/default-release/Mail/Local Folders/Inbox', 'invoice')
trash_invoices = count_active('/home/ga/.thunderbird/default-release/Mail/Local Folders/Trash', 'invoice')
inbox_spam = count_active('/home/ga/.thunderbird/default-release/Mail/Local Folders/Inbox', 'gift card')

print(json.dumps({
    "inbox_invoices": inbox_invoices,
    "trash_invoices": trash_invoices,
    "inbox_spam": inbox_spam
}))
EOF

MBOX_STATS=$(python3 /tmp/check_mbox.py)
INBOX_INVOICE_COUNT=$(echo "$MBOX_STATS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('inbox_invoices', 0))")
TRASH_INVOICE_COUNT=$(echo "$MBOX_STATS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('trash_invoices', 0))")
INBOX_SPAM_COUNT=$(echo "$MBOX_STATS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('inbox_spam', 0))")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "system_sync_exists": $SYSTEM_SYNC_EXISTS,
    "newsletter_exists": $NEWSLETTER_EXISTS,
    "inbox_invoice_count": $INBOX_INVOICE_COUNT,
    "trash_invoice_count": $TRASH_INVOICE_COUNT,
    "inbox_spam_count": $INBOX_SPAM_COUNT
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="