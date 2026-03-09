#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: categorize_tickets_with_tags ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure clean state
# Delete existing tags to ensure agent creates them
fs_query "DELETE FROM tags WHERE name IN ('Acme VIP', 'Urgent')"
fs_query "DELETE FROM conversation_tag"

# 2. Create Mailbox
MAILBOX_ID=$(ensure_mailbox_exists "Support" "support@helpdesk.local")
echo "Using Mailbox ID: $MAILBOX_ID"

# 3. Create Customers
echo "Creating customers..."
# Acme Corp Customer 1
ACME_CUST_1=$(fs_tinker "\$c = new \\App\\Customer(); \$c->first_name = 'Alice'; \$c->last_name = 'Vance'; \$c->save(); \$e = new \\App\\Email(); \$e->email = 'alice@acmecorp.com'; \$e->customer_id = \$c->id; \$e->save(); echo 'ID:'.\$c->id;")
ACME_CUST_1_ID=$(echo "$ACME_CUST_1" | grep 'ID:' | sed 's/ID://')

# Acme Corp Customer 2
ACME_CUST_2=$(fs_tinker "\$c = new \\App\\Customer(); \$c->first_name = 'Bob'; \$c->last_name = 'Myman'; \$c->save(); \$e = new \\App\\Email(); \$e->email = 'bob@acmecorp.com'; \$e->customer_id = \$c->id; \$e->save(); echo 'ID:'.\$c->id;")
ACME_CUST_2_ID=$(echo "$ACME_CUST_2" | grep 'ID:' | sed 's/ID://')

# Random Customer
RAND_CUST=$(fs_tinker "\$c = new \\App\\Customer(); \$c->first_name = 'Charlie'; \$c->last_name = 'Day'; \$c->save(); \$e = new \\App\\Email(); \$e->email = 'charlie@gmail.com'; \$e->customer_id = \$c->id; \$e->save(); echo 'ID:'.\$c->id;")
RAND_CUST_ID=$(echo "$RAND_CUST" | grep 'ID:' | sed 's/ID://')

# 4. Create Conversations
echo "Creating conversations..."

# Target 1: Acme
CONV1=$(create_conversation_via_orm "Question about enterprise billing" "$MAILBOX_ID" "alice@acmecorp.com" "$ACME_CUST_1_ID" "Hi, we need to update our billing address for the next invoice.")
echo "Created Acme Conv 1: $CONV1"

# Target 2: Acme
CONV2=$(create_conversation_via_orm "Feature request: SSO Integration" "$MAILBOX_ID" "bob@acmecorp.com" "$ACME_CUST_2_ID" "When will SSO be available for our tier?")
echo "Created Acme Conv 2: $CONV2"

# Target 3: Urgent
CONV3=$(create_conversation_via_orm "System Critical: Database Crash detected" "$MAILBOX_ID" "charlie@gmail.com" "$RAND_CUST_ID" "The production database just dumped core. Please assist immediately.")
echo "Created Urgent Conv: $CONV3"

# Distractor 1
create_conversation_via_orm "Just saying hello" "$MAILBOX_ID" "dave@yahoo.com" "" "Just testing the system." > /dev/null

# Distractor 2
create_conversation_via_orm "Password reset" "$MAILBOX_ID" "eve@hotmail.com" "" "I forgot my password again." > /dev/null

# Save Ground Truth IDs for verification (hidden from agent)
echo "$CONV1" > /tmp/gt_acme_id_1
echo "$CONV2" > /tmp/gt_acme_id_2
echo "$CONV3" > /tmp/gt_urgent_id

# Clear cache to ensure data appears
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# 5. Launch Firefox
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/mailbox/$MAILBOX_ID' > /dev/null 2>&1 &"
    sleep 5
fi

# Wait for window
wait_for_window "firefox|mozilla|freescout" 60
focus_firefox

# Ensure maximized
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="