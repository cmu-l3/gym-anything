#!/bin/bash
set -e
echo "=== Setting up edit_saved_reply task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# === Ensure mailbox exists ===
MAILBOX_ID=$(ensure_mailbox_exists "IT Support" "itsupport@helpdesk.local")
echo "Mailbox ID: $MAILBOX_ID"

# === Clean up previous runs ===
# Remove any saved replies that look like our target (old or new) to start fresh
fs_query "DELETE FROM saved_replies WHERE mailbox_id = $MAILBOX_ID AND (name LIKE '%Password Reset%' OR name LIKE '%SSO%')" 2>/dev/null || true

# === Create the saved reply with outdated content ===
# Get admin user ID
ADMIN_USER_ID=$(fs_query "SELECT id FROM users WHERE email='admin@helpdesk.local' LIMIT 1" 2>/dev/null | tr -cd '0-9')
if [ -z "$ADMIN_USER_ID" ]; then ADMIN_USER_ID=1; fi

# Content for the old saved reply
OLD_BODY="Hello,\n\nTo reset your password, please follow these steps:\n\n1. Navigate to https://legacy.internal.corp/reset\n2. Enter your username (usually your email address)\n3. Click the Reset Password button\n4. You will receive a password reset email within a few minutes\n5. Click the link in the email and choose a new password\n\nPlease ensure your new password is at least 8 characters long.\n\nIf you need further assistance, contact IT at extension 4500.\n\nRegards,\nIT Department"

# Insert directly via SQL to ensure it exists with known ID
fs_query "INSERT INTO saved_replies (mailbox_id, user_id, name, text, created_at, updated_at) VALUES ($MAILBOX_ID, $ADMIN_USER_ID, 'Password Reset Instructions', '$OLD_BODY', NOW(), NOW())"

# Get the ID of the created reply
TARGET_ID=$(fs_query "SELECT id FROM saved_replies WHERE mailbox_id = $MAILBOX_ID AND name = 'Password Reset Instructions' ORDER BY id DESC LIMIT 1" 2>/dev/null)
echo "$TARGET_ID" > /tmp/target_saved_reply_id.txt
echo "Created target Saved Reply ID: $TARGET_ID"

# Record initial count for anti-gaming (to detect if they just created a new one)
INITIAL_COUNT=$(fs_query "SELECT COUNT(*) FROM saved_replies WHERE mailbox_id = $MAILBOX_ID" 2>/dev/null)
echo "$INITIAL_COUNT" > /tmp/initial_count.txt

# === Prepare Browser ===
# Ensure Firefox is closed then open to login
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox
su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/login' > /tmp/firefox.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "firefox\|mozilla\|freescout"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Login if needed (helper function in task_utils handles check)
ensure_logged_in

# Navigate to the mailbox settings or main page to start
navigate_to_url "http://localhost:8080/mailbox/$MAILBOX_ID"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="