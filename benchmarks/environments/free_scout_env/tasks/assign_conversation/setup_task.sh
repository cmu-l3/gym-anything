#!/bin/bash
echo "=== Setting up assign_conversation task ==="

source /workspace/scripts/task_utils.sh

# Read customer data from the real Kaggle Customer Support Ticket Dataset
# Row with: Name="Frank Sherman", Email="floresbryan@example.net", Subject="Payment issue", Type="Billing inquiry"
# Source: chiapudding/kaggle-customer-service on HuggingFace/Kaggle
CUST_FIRST="Frank"
CUST_LAST="Sherman"
CUST_EMAIL="floresbryan@example.net"
CONV_SUBJECT="Payment issue"

CONV_BODY="I'm having an issue with my recent payment. I was charged twice for my USB-C Hub Pro order. The duplicate charge of \$89.99 appeared on my statement dated last week. Could you please investigate and process a refund for the duplicate charge? Thanks, Frank Sherman"

# Ensure a mailbox exists (creates folders via ORM)
MAILBOX_ID=$(ensure_mailbox_exists "Support" "support@helpdesk.local")
if [ -z "$MAILBOX_ID" ]; then
    MAILBOX_ID=$(fs_query "SELECT id FROM mailboxes ORDER BY id ASC LIMIT 1" 2>/dev/null || echo "1")
fi
echo "Using mailbox ID: $MAILBOX_ID"

# Get the admin user ID (the one we want the agent to assign to)
ADMIN_USER_ID=$(fs_query "SELECT id FROM users WHERE email = 'admin@helpdesk.local' LIMIT 1" 2>/dev/null || echo "1")
echo "Admin user ID: $ADMIN_USER_ID"

# Create a customer for the conversation
CUSTOMER_EXISTS=$(fs_query "SELECT id FROM customers WHERE first_name = '$CUST_FIRST' AND last_name = '$CUST_LAST' LIMIT 1" 2>/dev/null)
if [ -z "$CUSTOMER_EXISTS" ]; then
    fs_query "INSERT INTO customers (first_name, last_name, created_at, updated_at) VALUES ('$CUST_FIRST', '$CUST_LAST', NOW(), NOW())" 2>/dev/null || true
    CUSTOMER_ID=$(fs_query "SELECT id FROM customers WHERE first_name = '$CUST_FIRST' AND last_name = '$CUST_LAST' ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$CUSTOMER_ID" ]; then
        fs_query "INSERT INTO emails (customer_id, email) VALUES ($CUSTOMER_ID, '$CUST_EMAIL')" 2>/dev/null || true
    fi
else
    CUSTOMER_ID="$CUSTOMER_EXISTS"
fi
echo "Customer ID: $CUSTOMER_ID"

# Create an unassigned conversation via ORM
CONV_EXISTS=$(fs_query "SELECT id FROM conversations WHERE subject = '$CONV_SUBJECT' LIMIT 1" 2>/dev/null)
if [ -z "$CONV_EXISTS" ]; then
    CONV_ID=$(create_conversation_via_orm "$CONV_SUBJECT" "$MAILBOX_ID" "$CUST_EMAIL" "${CUSTOMER_ID:-}" "$CONV_BODY")
    echo "Created conversation ID: $CONV_ID"

    # Ensure it's unassigned
    if [ -n "$CONV_ID" ]; then
        fs_query "UPDATE conversations SET user_id = NULL WHERE id = $CONV_ID" 2>/dev/null || true
    fi
else
    CONV_ID="$CONV_EXISTS"
    # Ensure it's unassigned
    fs_query "UPDATE conversations SET user_id = NULL WHERE id = $CONV_ID" 2>/dev/null || true
fi
echo "Conversation ID: $CONV_ID"

# Clear FreeScout cache so conversation shows in UI
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# Record initial assignment state
echo "NULL" > /tmp/initial_assignee
echo "$CONV_ID" > /tmp/conversation_id

# Ensure Firefox is running and navigate to inbox
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox "http://localhost:8080/mailbox/${MAILBOX_ID}" > /tmp/firefox.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox|mozilla|freescout" 30
focus_firefox
navigate_to_url "http://localhost:8080/mailbox/${MAILBOX_ID}"
sleep 3

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
