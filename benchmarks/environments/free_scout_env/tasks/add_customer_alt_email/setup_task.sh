#!/bin/bash
echo "=== Setting up add_customer_alt_email task ==="

source /workspace/scripts/task_utils.sh

# 1. Create the Mailbox
MAILBOX_ID=$(ensure_mailbox_exists "Academic Support" "support@university.local")
echo "Using Mailbox ID: $MAILBOX_ID"

# 2. Define Customer Data
CUST_FIRST="Dr. Julian"
CUST_LAST="Blackwood"
CUST_EMAIL="julian.b@university.local"

# 3. Create Conversation (creates customer automatically)
# We create a ticket first so the customer exists in the system
CONV_SUBJECT="Access to archives expiring soon"
CONV_BODY="Hi, my university access is expiring soon. Can I link my new corporate email to this account?"

echo "Creating conversation..."
CONV_ID=$(create_conversation_via_orm "$CONV_SUBJECT" "$MAILBOX_ID" "$CUST_EMAIL" "" "$CONV_BODY")
echo "Created Conversation ID: $CONV_ID"

# 4. Update Customer Name
# The automatic creation usually uses the name from the email header or leaves it blank.
# We explicitly set the name to "Dr. Julian Blackwood" to ensure the agent can find them.
echo "Updating customer name..."
fs_tinker "
\$c = \App\Customer::whereHas('emails', function(\$q) {
    \$q->where('email', '$CUST_EMAIL');
})->first();
if (\$c) {
    \$c->first_name = '$CUST_FIRST';
    \$c->last_name = '$CUST_LAST';
    \$c->save();
    echo 'CUSTOMER_ID:' . \$c->id;
} else {
    echo 'CUSTOMER_NOT_FOUND';
}
"

# 5. Record Initial State (Timestamp)
date +%s > /tmp/task_start_time.txt
# Record that we started with 1 email for this customer
echo "1" > /tmp/initial_email_count.txt

# 6. Clear Cache
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# 7. Start Firefox and navigate to Dashboard
# We intentionally do NOT navigate to the customer page directly; agent must find them.
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox "http://localhost:8080" > /tmp/firefox.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox|mozilla|freescout" 30
focus_firefox
navigate_to_url "http://localhost:8080"
sleep 2

# 8. Take Initial Screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="