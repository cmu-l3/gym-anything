#!/bin/bash
set -e
echo "=== Setting up use_saved_reply_in_conversation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create Mailbox
MAILBOX_NAME="AV Service Desk"
MAILBOX_EMAIL="avservice@helpdesk.local"
MAILBOX_ID=$(ensure_mailbox_exists "$MAILBOX_NAME" "$MAILBOX_EMAIL")
echo "Mailbox ID: $MAILBOX_ID"

# 2. Create Saved Reply via ORM
# We use tinker to ensure it's created correctly with model logic
SAVED_REPLY_NAME="Maintenance Appointment Confirmation"
SAVED_REPLY_BODY="Thank you for contacting AV Service Desk regarding your maintenance request.

We have scheduled your equipment maintenance appointment. A certified technician will arrive at your location on the agreed date. Please ensure the following before the visit:

1. The equipment is powered off and accessible
2. A staff member is available to provide access to the room
3. Any recent error messages or issues are documented

If you need to reschedule, please reply to this message at least 24 hours in advance.

Best regards,
AV Service Team"

# Escape quotes for PHP string
ESCAPED_BODY=$(echo "$SAVED_REPLY_BODY" | sed "s/'/\\\\'/g")

echo "Creating Saved Reply..."
fs_tinker "
\$exists = \\App\\SavedReply::where('mailbox_id', $MAILBOX_ID)->where('name', '$SAVED_REPLY_NAME')->first();
if (!\$exists) {
    \$r = new \\App\\SavedReply();
    \$r->mailbox_id = $MAILBOX_ID;
    \$r->name = '$SAVED_REPLY_NAME';
    \$r->body = '$ESCAPED_BODY';
    \$r->save();
    echo 'SAVED_REPLY_ID:' . \$r->id;
} else {
    echo 'SAVED_REPLY_ID:' . \$exists->id;
}
"

# 3. Create Customer and Conversation
CUST_NAME="Rachel Torres"
CUST_EMAIL="rachel.torres@meridianav.com"
SUBJECT="Projector Maintenance Request - Conference Room B"
BODY="Hi,

I'm writing to request a maintenance appointment for the Epson Pro L1755U projector installed in Conference Room B. The projector has been displaying intermittent color calibration issues.

Could you please confirm availability and let us know what preparation is needed on our end?

Thank you,
Rachel Torres"

# Check if conversation exists
EXISTING_CONV=$(find_conversation_by_subject "$SUBJECT")

if [ -z "$EXISTING_CONV" ]; then
    # Create customer if needed
    CUST_ID=$(fs_query "SELECT id FROM customers WHERE id IN (SELECT customer_id FROM emails WHERE email='$CUST_EMAIL') LIMIT 1" 2>/dev/null)
    if [ -z "$CUST_ID" ]; then
        # Create customer via tinker
        CUST_ID=$(fs_tinker "
        \$c = new \\App\\Customer();
        \$c->first_name = 'Rachel';
        \$c->last_name = 'Torres';
        \$c->save();
        \$e = new \\App\\Email();
        \$e->email = '$CUST_EMAIL';
        \$e->customer_id = \$c->id;
        \$e->type = 'work';
        \$e->save();
        echo 'CUST_ID:' . \$c->id;
        " | grep 'CUST_ID:' | sed 's/CUST_ID://' | tr -cd '0-9')
    fi
    
    # Create conversation
    CONV_ID=$(create_conversation_via_orm "$SUBJECT" "$MAILBOX_ID" "$CUST_EMAIL" "$CUST_ID" "$BODY")
    echo "Created Conversation ID: $CONV_ID"
else
    CONV_ID=$(echo "$EXISTING_CONV" | cut -f1)
    echo "Using existing Conversation ID: $CONV_ID"
fi

# Store IDs for verification
echo "$CONV_ID" > /tmp/target_conversation_id.txt
echo "$MAILBOX_ID" > /tmp/target_mailbox_id.txt

# Record initial thread count
INITIAL_THREAD_COUNT=$(fs_query "SELECT COUNT(*) FROM threads WHERE conversation_id = $CONV_ID" 2>/dev/null || echo "1")
echo "$INITIAL_THREAD_COUNT" > /tmp/initial_thread_count.txt

# 4. Prepare Environment
# Clear cache to ensure new data appears
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# Launch Firefox
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/mailbox/$MAILBOX_ID' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|freescout"; then
        break
    fi
    sleep 1
done

# Focus and maximize
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Navigate to mailbox
navigate_to_url "http://localhost:8080/mailbox/$MAILBOX_ID"

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="