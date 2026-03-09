#!/bin/bash
set -e
echo "=== Setting up task: merge_duplicate_tickets ==="

# Source helpers
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure FreeScout is running
if ! pgrep -f "supervisord" > /dev/null && ! docker ps | grep -q "freescout-app"; then
    echo "Starting FreeScout..."
    /workspace/scripts/setup_freescout.sh
fi

# 1. Ensure Mailbox Exists
MAILBOX_ID=$(ensure_mailbox_exists "Support" "support@helpdesk.local")
echo "Using Mailbox ID: $MAILBOX_ID"

# 2. Create Customer
CUSTOMER_EMAIL="alice.chen@example.org"
# Check if customer exists, if not create
CUSTOMER_ID=$(fs_query "SELECT c.id FROM customers c JOIN emails e ON c.id = e.customer_id WHERE e.email = '$CUSTOMER_EMAIL' LIMIT 1")

if [ -z "$CUSTOMER_ID" ]; then
    echo "Creating customer Alice Chen..."
    # Create via ORM to handle related tables
    CUSTOMER_ID=$(fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = 'Alice';
\$c->last_name = 'Chen';
\$c->type = 1;
\$c->save();
\$e = new \\App\\Email();
\$e->email = '$CUSTOMER_EMAIL';
\$e->type = 1;
\$e->customer_id = \$c->id;
\$e->save();
echo 'CUST_ID:' . \$c->id;
" | grep 'CUST_ID:' | sed 's/CUST_ID://' | tr -cd '0-9')
fi
echo "Customer ID: $CUSTOMER_ID"

# 3. Create 3 Separate Conversations
# We use distinct body text to verify the merge later

# Conv 1
BODY_1="Hi support, I am just checking on my shipment for Order #8821. It has been 5 days."
create_conversation_via_orm "Order #8821 status question" "$MAILBOX_ID" "$CUSTOMER_EMAIL" "$CUSTOMER_ID" "$BODY_1" > /dev/null

# Conv 2
BODY_2="Sorry, I forgot to mention regarding Order #8821, I might have entered the wrong zip code."
create_conversation_via_orm "Forgot to mention regarding Order #8821" "$MAILBOX_ID" "$CUSTOMER_EMAIL" "$CUSTOMER_ID" "$BODY_2" > /dev/null

# Conv 3
BODY_3="Urgent: Order #8821 delivery address needs apartment number 4B added please!"
create_conversation_via_orm "Urgent: Order #8821 delivery address" "$MAILBOX_ID" "$CUSTOMER_EMAIL" "$CUSTOMER_ID" "$BODY_3" > /dev/null

echo "Created 3 conversations for Alice Chen."

# Clear cache to ensure they show up
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# 4. Launch/Focus Firefox
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox "http://localhost:8080/mailbox/$MAILBOX_ID" > /tmp/firefox.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox|mozilla|freescout" 30
focus_firefox
navigate_to_url "http://localhost:8080/mailbox/$MAILBOX_ID"
sleep 2

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take screenshot initial state
take_screenshot "/tmp/task_initial.png"

echo "=== Task setup complete ==="