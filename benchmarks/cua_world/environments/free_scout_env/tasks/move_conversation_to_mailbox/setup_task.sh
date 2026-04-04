#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up move_conversation_to_mailbox task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# ===== Create General Inquiries mailbox =====
echo "Creating General Inquiries mailbox..."
GENERAL_MAILBOX_ID=$(ensure_mailbox_exists "General Inquiries" "general@helpdesk.local")
if [ -z "$GENERAL_MAILBOX_ID" ]; then
    echo "ERROR: Failed to create General Inquiries mailbox"
    exit 1
fi
echo "General Inquiries mailbox ID: $GENERAL_MAILBOX_ID"

# ===== Create IT Network Support mailbox =====
echo "Creating IT Network Support mailbox..."
NETSUPPORT_MAILBOX_ID=$(ensure_mailbox_exists "IT Network Support" "netsupport@helpdesk.local")
if [ -z "$NETSUPPORT_MAILBOX_ID" ]; then
    echo "ERROR: Failed to create IT Network Support mailbox"
    exit 1
fi
echo "IT Network Support mailbox ID: $NETSUPPORT_MAILBOX_ID"

# Save mailbox IDs for verification
echo "$GENERAL_MAILBOX_ID" > /tmp/general_mailbox_id.txt
echo "$NETSUPPORT_MAILBOX_ID" > /tmp/netsupport_mailbox_id.txt

# ===== Create customer Marcus Chen =====
echo "Creating customer Marcus Chen..."
# We use tinker directly to ensure clean creation with specific email
CUSTOMER_ID=$(fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = 'Marcus';
\$c->last_name = 'Chen';
\$c->save();
\$email = new \\App\\Email();
\$email->customer_id = \$c->id;
\$email->email = 'marcus.chen@acmecorp.com';
\$email->save();
echo 'CUSTOMER_ID:' . \$c->id;
" | grep 'CUSTOMER_ID:' | sed 's/CUSTOMER_ID://' | tr -cd '0-9')

if [ -z "$CUSTOMER_ID" ]; then
    echo "WARNING: Customer creation may have failed, using fallback ID 1"
    CUSTOMER_ID="1"
fi
echo "Customer ID: $CUSTOMER_ID"

# ===== Create conversation in General Inquiries =====
echo "Creating conversation in General Inquiries mailbox..."
CONV_ID=$(create_conversation_via_orm \
    "Printer cannot connect to network after office move" \
    "$GENERAL_MAILBOX_ID" \
    "marcus.chen@acmecorp.com" \
    "$CUSTOMER_ID" \
    "Hi Support Team, after our office relocation to the 3rd floor last Friday, our HP LaserJet Pro M404dn printer (asset tag NET-2847) is unable to connect to the network. The printer shows a network error on its display panel and is not reachable by any workstation on the subnet. We have verified the Ethernet cable is plugged in and the wall jack at port 3F-J12 is active per the facilities team. The printer was working fine at its previous location on the 2nd floor. Could someone from the IT networking team investigate? This is affecting 12 people in the Facilities department who rely on this printer for daily operations. Please advise on next steps. Thanks, Marcus Chen - Facilities Coordinator, Ext. 4281")

if [ -z "$CONV_ID" ]; then
    echo "ERROR: Failed to create conversation"
    exit 1
fi
echo "Conversation ID: $CONV_ID"

# Save conversation ID for verification
echo "$CONV_ID" > /tmp/conversation_id.txt

# Record initial mailbox_id for verification
INITIAL_MAILBOX_ID=$(fs_query "SELECT mailbox_id FROM conversations WHERE id = $CONV_ID" 2>/dev/null | tr -cd '0-9')
echo "$INITIAL_MAILBOX_ID" > /tmp/initial_mailbox_id.txt
echo "Initial mailbox_id: $INITIAL_MAILBOX_ID"

# Wait for data to settle
sleep 3

# ===== Ensure admin user has access to both mailboxes =====
echo "Granting admin access to both mailboxes..."
ADMIN_USER_ID=$(fs_query "SELECT id FROM users WHERE email = 'admin@helpdesk.local' LIMIT 1" 2>/dev/null | tr -cd '0-9')
if [ -n "$ADMIN_USER_ID" ]; then
    fs_tinker "
\$user = \\App\\User::find($ADMIN_USER_ID);
if (\$user) {
    \$user->mailboxes()->syncWithoutDetaching([$GENERAL_MAILBOX_ID, $NETSUPPORT_MAILBOX_ID]);
    echo 'ACCESS_GRANTED';
}
" > /dev/null 2>&1
    echo "Admin (ID: $ADMIN_USER_ID) granted access to both mailboxes"
fi

# ===== Navigate Firefox to the General Inquiries mailbox =====
echo "Navigating Firefox to General Inquiries mailbox..."
focus_firefox
sleep 1
navigate_to_url "http://localhost:8080/mailbox/${GENERAL_MAILBOX_ID}"
sleep 5

# Maximize Firefox window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Conversation ID $CONV_ID is in General Inquiries (mailbox $GENERAL_MAILBOX_ID)"
echo "Target: Move to IT Network Support (mailbox $NETSUPPORT_MAILBOX_ID)"