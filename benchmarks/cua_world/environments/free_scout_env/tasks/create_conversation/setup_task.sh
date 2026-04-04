#!/bin/bash
echo "=== Setting up create_conversation task ==="

source /workspace/scripts/task_utils.sh

# Ensure a default mailbox exists for conversation creation
# The admin setup should have created at least one mailbox, but verify
MAILBOX_COUNT=$(get_mailbox_count)
echo "Current mailbox count: $MAILBOX_COUNT"

if [ "$MAILBOX_COUNT" -lt "1" ]; then
    echo "No mailboxes found. Creating a default mailbox via ORM..."
    CREATED_ID=$(ensure_mailbox_exists "Support" "support@helpdesk.local")
    echo "Created mailbox ID: $CREATED_ID"
    sleep 2
    MAILBOX_COUNT=$(get_mailbox_count)
    echo "Mailbox count after creation: $MAILBOX_COUNT"
fi

# Record initial conversation count
INITIAL_COUNT=$(get_conversation_count)
echo "$INITIAL_COUNT" > /tmp/initial_conversation_count
echo "Initial conversation count: $INITIAL_COUNT"

# Record initial customer count
INITIAL_CUSTOMER_COUNT=$(get_customer_count)
echo "$INITIAL_CUSTOMER_COUNT" > /tmp/initial_customer_count

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080' > /tmp/firefox.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox|mozilla|freescout" 30
focus_firefox
navigate_to_url "http://localhost:8080"
sleep 3

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
