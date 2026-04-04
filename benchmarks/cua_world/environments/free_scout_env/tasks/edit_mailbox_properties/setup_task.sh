#!/bin/bash
set -e
echo "=== Setting up edit_mailbox_properties task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create the specific mailbox to be edited
# We use the ORM helper to ensure it's created correctly with folders
TARGET_NAME="Equipment Intake"
TARGET_EMAIL="intake@helpdesk.local"

echo "Creating target mailbox..."
MAILBOX_ID=$(ensure_mailbox_exists "$TARGET_NAME" "$TARGET_EMAIL")
echo "Target Mailbox ID: $MAILBOX_ID"
echo "$MAILBOX_ID" > /tmp/target_mailbox_id.txt

# 2. Record initial state for anti-gaming (count should stay same)
INITIAL_COUNT=$(get_mailbox_count)
echo "$INITIAL_COUNT" > /tmp/initial_mailbox_count.txt
echo "Initial mailbox count: $INITIAL_COUNT"

# 3. Ensure Firefox is running and logged in
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    # Launch directly to dashboard
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/dashboard' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# 4. Wait for window and focus
wait_for_window "firefox\|mozilla\|freescout" 30
focus_firefox

# 5. Navigate to Dashboard to start fresh
navigate_to_url "http://localhost:8080/dashboard"
sleep 2

# 6. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Target Mailbox: $TARGET_NAME ($TARGET_EMAIL)"
echo "Goal: Rename to 'Field Service Requests', change email to 'fieldservice@helpdesk.local', add alias 'equipmentintake@helpdesk.local'"