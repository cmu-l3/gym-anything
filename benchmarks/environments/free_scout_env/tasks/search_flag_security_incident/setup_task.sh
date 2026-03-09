#!/bin/bash
set -e
echo "=== Setting up search_flag_security_incident task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ===== Setup Data =====
MAILBOX_NAME="IT Helpdesk"
MAILBOX_EMAIL="helpdesk@company.local"

# 1. Create Mailbox
echo "Creating mailbox..."
MAILBOX_ID=$(ensure_mailbox_exists "$MAILBOX_NAME" "$MAILBOX_EMAIL")
echo "Mailbox ID: $MAILBOX_ID"

# 2. Create Users
# Admin exists by default.

# 3. Create Customers
echo "Creating customers..."

# Target Customer: Sarah Jones
CUST_TARGET_ID=$(fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = 'Sarah';
\$c->last_name = 'Jones';
\$c->type = 1;
\$c->save();
\$e = new \\App\\Email();
\$e->email = 'sarah.jones@marketing-partner.net';
\$e->type = 1;
\$e->customer_id = \$c->id;
\$e->save();
echo 'ID:' . \$c->id;
" | grep 'ID:' | sed 's/ID://' | tr -cd '0-9')

# Distractor 1: Bob Smith
CUST_D1_ID=$(fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = 'Bob';
\$c->last_name = 'Smith';
\$c->save();
\$e = new \\App\\Email();
\$e->email = 'bob.smith@local.org';
\$e->customer_id = \$c->id;
\$e->save();
echo 'ID:' . \$c->id;
" | grep 'ID:' | sed 's/ID://' | tr -cd '0-9')

# Distractor 2: Netflix Support (Spam)
CUST_D2_ID=$(fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = 'Netflix';
\$c->last_name = 'Support';
\$c->save();
\$e = new \\App\\Email();
\$e->email = 'alert@netflix-verify-account.com';
\$e->customer_id = \$c->id;
\$e->save();
echo 'ID:' . \$c->id;
" | grep 'ID:' | sed 's/ID://' | tr -cd '0-9')

# 4. Create Conversations
echo "Creating conversations..."

# TARGET TICKET
TARGET_CONV_ID=$(create_conversation_via_orm \
    "Suspicious invoice attached - urgent check needed" \
    "$MAILBOX_ID" \
    "sarah.jones@marketing-partner.net" \
    "$CUST_TARGET_ID" \
    "Hi IT, I received this invoice attached but I didn't order anything from this vendor. Is this a phishing attempt? The sender domain looks slightly off. Please advise.")

echo "TARGET_CONV_ID=$TARGET_CONV_ID" > /tmp/target_conv_id.txt

# Distractor 1 (Legit Invoice - Keyword overlap 'invoice')
D1_CONV_ID=$(create_conversation_via_orm \
    "Invoice #99283 approval required" \
    "$MAILBOX_ID" \
    "bob.smith@local.org" \
    "$CUST_D1_ID" \
    "Hi team, submitting the attached invoice for the new monitors. Please process payment.")
echo "$D1_CONV_ID" >> /tmp/distractor_ids.txt

# Distractor 2 (Spam - Keyword overlap 'Suspicious')
D2_CONV_ID=$(create_conversation_via_orm \
    "Suspicious activity detected on your account" \
    "$MAILBOX_ID" \
    "alert@netflix-verify-account.com" \
    "$CUST_D2_ID" \
    "Your account has been suspended due to suspicious activity. Click here to verify.")
echo "$D2_CONV_ID" >> /tmp/distractor_ids.txt

# Distractor 3 (Keyword overlap 'security')
D3_CONV_ID=$(create_conversation_via_orm \
    "Update on security training" \
    "$MAILBOX_ID" \
    "bob.smith@local.org" \
    "$CUST_D1_ID" \
    "Just a reminder that the annual security phishing training is due next week.")
echo "$D3_CONV_ID" >> /tmp/distractor_ids.txt

# Clear cache to ensure data appears
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# 5. Environment Prep
# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox "http://localhost:8080/mailbox/$MAILBOX_ID" > /tmp/firefox.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox|mozilla|freescout" 30
focus_firefox
navigate_to_url "http://localhost:8080/mailbox/$MAILBOX_ID"
sleep 2

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="