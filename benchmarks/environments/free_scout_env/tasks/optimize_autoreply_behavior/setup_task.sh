#!/bin/bash
set -e
echo "=== Setting up optimize_autoreply_behavior task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ===== 1. Ensure Facilities mailbox exists =====
echo "Ensuring Facilities mailbox exists..."
MAILBOX_ID=$(ensure_mailbox_exists "Facilities" "facilities@helpdesk.local")
echo "Mailbox ID: $MAILBOX_ID"
echo "$MAILBOX_ID" > /tmp/target_mailbox_id.txt

# ===== 2. Set Initial "Bad" State (Enabled for both) =====
# We want: Global=ON, New=ON, Reply=ON (Bad state: replies trigger loops)
# Columns in FreeScout mailboxes table: is_auto_reply, is_auto_reply_new, is_auto_reply_reply
echo "Configuring initial state (enabling all auto-replies)..."
fs_query "UPDATE mailboxes SET is_auto_reply=1, is_auto_reply_new=1, is_auto_reply_reply=1 WHERE id=$MAILBOX_ID"

# Verify initial state
INITIAL_STATE=$(fs_query "SELECT is_auto_reply, is_auto_reply_new, is_auto_reply_reply FROM mailboxes WHERE id=$MAILBOX_ID" 2>/dev/null)
echo "Initial DB State (Global, New, Reply): $INITIAL_STATE"
echo "$INITIAL_STATE" > /tmp/initial_db_state.txt

# ===== 3. Launch Firefox =====
# Start Firefox if not running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    # Navigate directly to the mailbox settings if possible, or dashboard
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/mailbox/$MAILBOX_ID/settings/auto-reply' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Wait for window
wait_for_window "firefox|mozilla|freescout" 30

# Focus and maximize
focus_firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# If already running, navigate to the target page to be helpful
navigate_to_url "http://localhost:8080/mailbox/$MAILBOX_ID/settings/auto-reply"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="