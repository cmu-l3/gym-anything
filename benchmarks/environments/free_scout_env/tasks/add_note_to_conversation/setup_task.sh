#!/bin/bash
echo "=== Setting up add_note_to_conversation task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure the Mailbox exists
MAILBOX_NAME="Network Support"
MAILBOX_EMAIL="network@helpdesk.local"
MAILBOX_ID=$(ensure_mailbox_exists "$MAILBOX_NAME" "$MAILBOX_EMAIL")
echo "Mailbox '$MAILBOX_NAME' ID: $MAILBOX_ID"

# 2. Ensure Customer exists
CUST_FIRST="Marcus"
CUST_LAST="Rivera"
CUST_EMAIL="marcus.rivera@acmecorp.com"

# Check if customer exists, create if not
CUSTOMER_DATA=$(find_customer_by_email "$CUST_EMAIL")
if [ -z "$CUSTOMER_DATA" ]; then
    echo "Creating customer $CUST_FIRST $CUST_LAST..."
    # Create via ORM to ensure proper linking
    CUST_ID=$(fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = '$CUST_FIRST';
\$c->last_name = '$CUST_LAST';
\$c->save();
\$email = new \\App\\Email();
\$email->customer_id = \$c->id;
\$email->email = '$CUST_EMAIL';
\$email->type = 'work';
\$email->save();
echo 'CUST_ID:' . \$c->id;
" | grep 'CUST_ID:' | sed 's/CUST_ID://' | tr -cd '0-9')
else
    CUST_ID=$(echo "$CUSTOMER_DATA" | cut -f1)
fi
echo "Customer ID: $CUST_ID"

# 3. Create the target conversation
CONV_SUBJECT="VPN connection drops intermittently from Building C"
CONV_BODY="Hi Support,\n\nI'm in Building C today and my VPN keeps dropping every 5-10 minutes. It's making it impossible to join Teams meetings. I've tried rebooting but it persists.\n\nCan you check the network?\n\nThanks,\nMarcus"

# Check if conversation already exists to avoid duplicates on retry
EXISTING_CONV=$(find_conversation_by_subject "$CONV_SUBJECT")

if [ -z "$EXISTING_CONV" ]; then
    echo "Creating conversation..."
    CONV_ID=$(create_conversation_via_orm "$CONV_SUBJECT" "$MAILBOX_ID" "$CUST_EMAIL" "$CUST_ID" "$CONV_BODY")
else
    CONV_ID=$(echo "$EXISTING_CONV" | cut -f1)
    echo "Conversation already exists."
fi
echo "Target Conversation ID: $CONV_ID"

# 4. Record Task Start Time (CRITICAL for anti-gaming)
# We only want to score notes created AFTER this timestamp
date '+%Y-%m-%d %H:%M:%S' > /tmp/task_start_timestamp.txt
date +%s > /tmp/task_start_time.txt

# 5. Record initial thread count for this conversation
INITIAL_THREAD_COUNT=$(fs_query "SELECT COUNT(*) FROM threads WHERE conversation_id = $CONV_ID" 2>/dev/null || echo "0")
echo "$INITIAL_THREAD_COUNT" > /tmp/initial_thread_count.txt

# 6. Clear Cache
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# 7. Setup Browser
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/login' > /tmp/firefox.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox|mozilla|freescout" 30
focus_firefox
navigate_to_url "http://localhost:8080/login"
sleep 2

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="