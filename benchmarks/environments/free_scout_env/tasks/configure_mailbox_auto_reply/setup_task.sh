#!/bin/bash
set -e
echo "=== Setting up configure_mailbox_auto_reply task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Create the target mailbox if it doesn't exist
# We use the helper to ensure it exists and get its ID
MAILBOX_ID=$(ensure_mailbox_exists "IT Support" "it-support@helpdesk.local")
echo "Target Mailbox ID: $MAILBOX_ID"
echo "$MAILBOX_ID" > /tmp/target_mailbox_id.txt

# 3. Reset auto-reply state to ensure a clean start
# We want to make sure it's disabled and empty so we can verify the agent actually did the work
echo "Resetting auto-reply configuration..."
fs_query "UPDATE mailboxes SET auto_reply_enabled = 0, auto_reply_subject = '', auto_reply_message = '' WHERE id = $MAILBOX_ID"

# Record initial state for verification (should be 0)
INITIAL_STATE=$(fs_query "SELECT auto_reply_enabled FROM mailboxes WHERE id = $MAILBOX_ID" 2>/dev/null || echo "0")
echo "$INITIAL_STATE" > /tmp/initial_auto_reply_state.txt

# 4. Clear application cache to ensure DB changes are reflected
docker exec freescout-app php /www/html/artisan cache:clear >/dev/null 2>&1 || true

# 5. Launch Firefox and login
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/login' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# 6. Wait for window and maximize
wait_for_window "firefox\|mozilla\|freescout" 60
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Ensure logged in
ensure_logged_in

# Navigate to dashboard
navigate_to_url "http://localhost:8080"

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="