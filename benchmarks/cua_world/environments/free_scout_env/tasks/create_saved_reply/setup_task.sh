#!/bin/bash
set -e
echo "=== Setting up create_saved_reply task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure IT Support mailbox exists
echo "Ensuring IT Support mailbox exists..."
MAILBOX_ID=$(ensure_mailbox_exists "IT Support" "itsupport@helpdesk.local")
echo "IT Support Mailbox ID: $MAILBOX_ID"
echo "$MAILBOX_ID" > /tmp/expected_mailbox_id.txt

# Clean up any previous saved replies with this name to ensure clean state
echo "Cleaning up old saved replies..."
fs_query "DELETE FROM saved_replies WHERE LOWER(name) LIKE '%password reset instructions%'" 2>/dev/null || true

# Record initial count of saved replies
INITIAL_COUNT=$(fs_query "SELECT COUNT(*) FROM saved_replies" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_saved_reply_count.txt
echo "Initial saved reply count: $INITIAL_COUNT"

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' > /tmp/firefox.log 2>&1 &"
    sleep 8
fi

# Wait for window and focus
wait_for_window "firefox\|mozilla\|freescout" 30
focus_firefox

# Navigate to dashboard
navigate_to_url "http://localhost:8080"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="