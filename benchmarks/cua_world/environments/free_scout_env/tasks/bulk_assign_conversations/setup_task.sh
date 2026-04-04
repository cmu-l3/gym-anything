#!/bin/bash
set -e
echo "=== Setting up bulk_assign_conversations task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Mailbox "Technical Support" exists
MAILBOX_NAME="Technical Support"
MAILBOX_EMAIL="tech@helpdesk.local"
MAILBOX_ID=$(ensure_mailbox_exists "$MAILBOX_NAME" "$MAILBOX_EMAIL")
echo "Using Mailbox ID: $MAILBOX_ID"

# 2. Ensure User "Marcus Chen" exists
AGENT_FIRST="Marcus"
AGENT_LAST="Chen"
AGENT_EMAIL="m.chen@helpdesk.local"
AGENT_PASS="Marcus123!"

# Check if user exists
AGENT_EXISTS=$(find_user_by_email "$AGENT_EMAIL")
if [ -z "$AGENT_EXISTS" ]; then
    echo "Creating agent $AGENT_FIRST $AGENT_LAST..."
    # Create via ORM/Tinker to ensure proper hashing and permissions
    AGENT_ID=$(fs_tinker "
\$u = new \\App\\User();
\$u->first_name = '$AGENT_FIRST';
\$u->last_name = '$AGENT_LAST';
\$u->email = '$AGENT_EMAIL';
\$u->password = bcrypt('$AGENT_PASS');
\$u->role = 'user';
\$u->save();
// Give access to mailbox
\$u->mailboxes()->syncWithoutDetaching([$MAILBOX_ID]);
echo 'USER_ID:' . \$u->id;
" | grep 'USER_ID:' | sed 's/USER_ID://' | tr -cd '0-9')
else
    AGENT_ID=$(echo "$AGENT_EXISTS" | cut -f1)
    # Ensure access to mailbox
    fs_tinker "\$u = \\App\\User::find($AGENT_ID); \$u->mailboxes()->syncWithoutDetaching([$MAILBOX_ID]);" > /dev/null
fi
echo "Agent ID: $AGENT_ID"

# 3. Create 5 Unassigned Conversations
# We will store their IDs to verify them specifically later
rm -f /tmp/target_conversation_ids.txt

declare -A TICKETS
TICKETS[0]="VPN connection drops every 15 minutes on Windows 11|Sarah Mitchell|sarah.m@example.com"
TICKETS[1]="Cannot print to HP LaserJet on 4th floor after network upgrade|James Whitfield|j.whitfield@example.org"
TICKETS[2]="Outlook keeps asking for password after O365 migration|Patricia Reeves|preeves@example.net"
TICKETS[3]="New laptop setup request for onboarding employee starting May 12|Tom Nakamura|t.nakamura@example.com"
TICKETS[4]="Shared drive S: not mapping on login - Accounting department|Linda Kowalski|linda.k@example.org"

echo "Creating 5 conversations..."
for i in "${!TICKETS[@]}"; do
    IFS='|' read -r SUBJECT NAME EMAIL <<< "${TICKETS[$i]}"
    
    # Create customer if needed (simplified)
    # We use the ORM helper which handles customer creation/lookup by email inside the logic usually, 
    # but here we'll just pass the email. create_conversation_via_orm handles customer creation if ID not provided?
    # Actually create_conversation_via_orm in task_utils takes (subject, mailbox_id, customer_email, customer_id, body)
    
    # Let's verify if customer exists to be safe, or just pass email
    BODY="Hi support, I need help with: $SUBJECT. Thanks, $NAME"
    
    CONV_ID=$(create_conversation_via_orm "$SUBJECT" "$MAILBOX_ID" "$EMAIL" "" "$BODY")
    
    # Ensure it is UNASSIGNED (user_id = NULL)
    fs_query "UPDATE conversations SET user_id = NULL, status = 1, state = 2 WHERE id = $CONV_ID"
    
    echo "$CONV_ID" >> /tmp/target_conversation_ids.txt
    echo "Created Conversation $CONV_ID: $SUBJECT"
done

# Clear cache to ensure UI updates
docker exec freescout-app php /www/html/artisan cache:clear > /dev/null 2>&1

# 4. Prepare Browser
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox "http://localhost:8080/mailbox/$MAILBOX_ID" > /tmp/firefox.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox|mozilla|freescout" 30
focus_firefox
navigate_to_url "http://localhost:8080/mailbox/$MAILBOX_ID"

# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Capture Initial State
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Target IDs saved to /tmp/target_conversation_ids.txt"
cat /tmp/target_conversation_ids.txt