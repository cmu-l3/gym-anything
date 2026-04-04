#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up organize_saved_replies task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# ===== Create the Mailbox =====
echo "Creating Customer Support mailbox..."
MAILBOX_ID=$(ensure_mailbox_exists "Customer Support" "support@helpdesk.local")
echo "Mailbox ID: $MAILBOX_ID"
echo "$MAILBOX_ID" > /tmp/task_mailbox_id.txt

# ===== Ensure Clean State (No 'Billing' Category) =====
echo "Cleaning up any existing Billing categories..."
fs_tinker "
\\App\\SavedReplyCategory::where('mailbox_id', $MAILBOX_ID)->where('name', 'Billing')->delete();
" > /dev/null

# ===== Create the Saved Reply (Uncategorized) =====
echo "Creating unorganized Saved Reply..."

# Check if it already exists to avoid duplicates/errors
EXISTING_REPLY_ID=$(fs_query "SELECT id FROM saved_replies WHERE mailbox_id=$MAILBOX_ID AND name='Refund Template' LIMIT 1" 2>/dev/null)

if [ -n "$EXISTING_REPLY_ID" ]; then
    echo "Found existing reply ID: $EXISTING_REPLY_ID"
    REPLY_ID="$EXISTING_REPLY_ID"
    # Reset state: ensure name is 'Refund Template' and no category
    fs_tinker "
\$r = \\App\\SavedReply::find($REPLY_ID);
if (\$r) {
    \$r->name = 'Refund Template';
    \$r->category_id = null;
    \$r->save();
}
" > /dev/null
else
    # Create new
    REPLY_RESULT=$(fs_tinker "
\$r = new \\App\\SavedReply();
\$r->mailbox_id = $MAILBOX_ID;
\$r->type = 1; // 1 = Text
\$r->name = 'Refund Template';
\$r->body = 'Dear customer, we have processed your refund. It should appear in 3-5 business days.';
\$r->user_id = 1; // Admin
\$r->save();
echo 'REPLY_ID:' . \$r->id;
")
    REPLY_ID=$(echo "$REPLY_RESULT" | grep 'REPLY_ID:' | sed 's/REPLY_ID://' | tr -cd '0-9')
fi

echo "Saved Reply ID: $REPLY_ID"
echo "$REPLY_ID" > /tmp/task_reply_id.txt

# ===== Firefox Setup =====
# Ensure Firefox is open and logged in
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' > /tmp/firefox.log 2>&1 &"
    sleep 10
fi

# Wait for window and focus
wait_for_window "firefox|mozilla|freescout" 30
focus_firefox
navigate_to_url "http://localhost:8080/mailbox/$MAILBOX_ID"
sleep 2

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="