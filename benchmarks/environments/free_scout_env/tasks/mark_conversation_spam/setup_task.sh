#!/bin/bash
set -e
echo "=== Setting up mark_conversation_spam task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure FreeScout is running
if ! curl -s "http://localhost:8080/login" > /dev/null; then
    echo "Waiting for FreeScout..."
    sleep 10
fi

# 1. Create specific Mailbox "IT Support"
MAILBOX_ID=$(ensure_mailbox_exists "IT Support" "itsupport@helpdesk.local")
echo "Using Mailbox ID: $MAILBOX_ID"
echo "$MAILBOX_ID" > /tmp/task_mailbox_id.txt

# 2. Create Customer "IT Security Team"
CUSTOMER_EMAIL="security-alert@external-verify.net"
CUSTOMER_ID=$(fs_tinker "
\$existing = \\App\\Email::where('email', '$CUSTOMER_EMAIL')->first();
if (\$existing) {
    echo 'CUSTOMER_ID:' . \$existing->customer_id;
} else {
    \$c = new \\App\\Customer();
    \$c->first_name = 'IT Security';
    \$c->last_name = 'Team';
    \$c->save();
    \$e = new \\App\\Email();
    \$e->customer_id = \$c->id;
    \$e->email = '$CUSTOMER_EMAIL';
    \$e->save();
    echo 'CUSTOMER_ID:' . \$c->id;
}
" | grep 'CUSTOMER_ID:' | sed 's/CUSTOMER_ID://' | tr -cd '0-9')
echo "Customer ID: $CUSTOMER_ID"

# 3. Create the Phishing Conversation
CONV_SUBJECT="URGENT: Your IT credentials expire today - immediate action required"
CONV_BODY="Dear Team Member, Our records indicate that your network credentials are scheduled to expire today. To avoid service disruption, you must verify your identity immediately by visiting the secure portal below. Failure to complete verification within 24 hours will result in permanent account suspension. This is an automated message from your IT Security Department. Please do not reply to this email. Visit: hxxp://credential-update.external-verify.net/login"

# Check if it already exists to avoid duplicates on retry
EXISTING_CONV=$(fs_query "SELECT id FROM conversations WHERE subject = '$CONV_SUBJECT' AND mailbox_id = $MAILBOX_ID LIMIT 1" 2>/dev/null)

if [ -n "$EXISTING_CONV" ]; then
    CONV_ID="$EXISTING_CONV"
    # Reset status to Active (1) and folder to Unassigned just in case
    # Unassigned folder is type 1
    UNASSIGNED_FOLDER=$(fs_query "SELECT id FROM folders WHERE mailbox_id = $MAILBOX_ID AND type = 1 LIMIT 1" 2>/dev/null)
    fs_query "UPDATE conversations SET status = 1, folder_id = $UNASSIGNED_FOLDER WHERE id = $CONV_ID" 2>/dev/null
    echo "Reset existing conversation ID: $CONV_ID"
else
    CONV_ID=$(create_conversation_via_orm "$CONV_SUBJECT" "$MAILBOX_ID" "$CUSTOMER_EMAIL" "$CUSTOMER_ID" "$CONV_BODY")
    echo "Created new conversation ID: $CONV_ID"
fi

echo "$CONV_ID" > /tmp/task_conversation_id.txt

# Clear cache to ensure it shows up
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# 4. Prepare Firefox
# Kill existing firefox to ensure clean state
pkill -f firefox 2>/dev/null || true
sleep 1

# Launch Firefox to login page
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/login' > /tmp/firefox.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|Mozilla\|FreeScout" 45

# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Target Conversation ID: $CONV_ID"
echo "Target Mailbox ID: $MAILBOX_ID"