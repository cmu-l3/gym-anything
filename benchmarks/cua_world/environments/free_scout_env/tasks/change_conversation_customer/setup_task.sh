#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up change_conversation_customer task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# ===== Create the Campus Security mailbox =====
echo "Creating Campus Security mailbox..."
MAILBOX_ID=$(ensure_mailbox_exists "Campus Security" "security@securecampus.com")
echo "Mailbox ID: $MAILBOX_ID"
echo "$MAILBOX_ID" > /tmp/mailbox_id.txt

# ===== Create the "Security Desk" customer (wrong/initial) =====
echo "Creating Security Desk customer..."
WRONG_CUSTOMER_RESULT=$(fs_tinker "
\$c = new \App\Customer();
\$c->first_name = 'Security';
\$c->last_name = 'Desk';
\$c->save();
\$email = new \App\Email();
\$email->customer_id = \$c->id;
\$email->email = 'security.desk@securecampus.com';
\$email->save();
echo 'CUSTOMER_ID:' . \$c->id;
")
WRONG_CUSTOMER_ID=$(echo "$WRONG_CUSTOMER_RESULT" | grep 'CUSTOMER_ID:' | sed 's/CUSTOMER_ID://' | tr -cd '0-9')
echo "Security Desk customer ID: $WRONG_CUSTOMER_ID"
echo "$WRONG_CUSTOMER_ID" > /tmp/wrong_customer_id.txt

# ===== Create the "James Whitfield" customer (correct/target) =====
echo "Creating James Whitfield customer..."
CORRECT_CUSTOMER_RESULT=$(fs_tinker "
\$c = new \App\Customer();
\$c->first_name = 'James';
\$c->last_name = 'Whitfield';
\$c->save();
\$email = new \App\Email();
\$email->customer_id = \$c->id;
\$email->email = 'james.whitfield@securecampus.com';
\$email->save();
echo 'CUSTOMER_ID:' . \$c->id;
")
CORRECT_CUSTOMER_ID=$(echo "$CORRECT_CUSTOMER_RESULT" | grep 'CUSTOMER_ID:' | sed 's/CUSTOMER_ID://' | tr -cd '0-9')
echo "James Whitfield customer ID: $CORRECT_CUSTOMER_ID"
echo "$CORRECT_CUSTOMER_ID" > /tmp/correct_customer_id.txt

# ===== Create the conversation associated with wrong customer =====
INCIDENT_BODY="At approximately 02:47 AM on the night shift, motion sensors triggered in the Building C server room corridor. Badge reader logs show three failed access attempts using a deactivated employee badge (ID: MCC-2019-0847). Physical inspection revealed no signs of forced entry. Recommending immediate badge audit."

echo "Creating conversation..."
CONV_ID=$(create_conversation_via_orm \
    "Unauthorized Access Attempt - Building C Server Room" \
    "$MAILBOX_ID" \
    "security.desk@securecampus.com" \
    "$WRONG_CUSTOMER_ID" \
    "$INCIDENT_BODY")

echo "Conversation ID: $CONV_ID"
echo "$CONV_ID" > /tmp/conversation_id.txt

# Record initial state details for integrity check
INITIAL_CID=$(fs_query "SELECT customer_id FROM conversations WHERE id = $CONV_ID" 2>/dev/null)
echo "$INITIAL_CID" > /tmp/initial_customer_id.txt

# ===== Navigate Firefox to FreeScout =====
echo "Navigating Firefox to FreeScout..."
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox "http://localhost:8080/mailbox/$MAILBOX_ID" > /tmp/firefox.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox|mozilla|freescout" 30
focus_firefox
navigate_to_url "http://localhost:8080/mailbox/$MAILBOX_ID"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="