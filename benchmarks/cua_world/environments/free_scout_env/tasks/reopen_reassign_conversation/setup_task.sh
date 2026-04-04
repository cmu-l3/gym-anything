#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up reopen_reassign_conversation task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure FreeScout is running
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/login" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "302" ]; then
    echo "ERROR: FreeScout not accessible (HTTP $HTTP_CODE)"
    exit 1
fi

# Create mailbox "IT Support"
MAILBOX_ID=$(ensure_mailbox_exists "IT Support" "it-support@helpdesk.local")
echo "Mailbox ID: $MAILBOX_ID"

if [ -z "$MAILBOX_ID" ]; then
    echo "ERROR: Failed to create mailbox"
    exit 1
fi

# Create user Marcus Chen (original assignee - on vacation)
MARCUS_RESULT=$(fs_tinker "
\$existing = \\App\\User::where('email', 'marcus.chen@helpdesk.local')->first();
if (\$existing) { echo 'USER_ID:' . \$existing->id; exit; }
\$u = new \\App\\User();
\$u->first_name = 'Marcus';
\$u->last_name = 'Chen';
\$u->email = 'marcus.chen@helpdesk.local';
\$u->password = bcrypt('Password123!');
\$u->role = 2;
\$u->save();
echo 'USER_ID:' . \$u->id;
")
MARCUS_ID=$(echo "$MARCUS_RESULT" | grep 'USER_ID:' | sed 's/USER_ID://' | tr -cd '0-9')
echo "Marcus Chen ID: $MARCUS_ID"

if [ -z "$MARCUS_ID" ]; then
    echo "ERROR: Failed to create Marcus Chen user"
    exit 1
fi

# Give Marcus access to IT Support mailbox
fs_tinker "
\$user = \\App\\User::find($MARCUS_ID);
\$user->mailboxes()->syncWithoutDetaching([$MAILBOX_ID]);
" > /dev/null 2>&1

# Create user Priya Sharma (new assignee - covering for Marcus)
PRIYA_RESULT=$(fs_tinker "
\$existing = \\App\\User::where('email', 'priya.sharma@helpdesk.local')->first();
if (\$existing) { echo 'USER_ID:' . \$existing->id; exit; }
\$u = new \\App\\User();
\$u->first_name = 'Priya';
\$u->last_name = 'Sharma';
\$u->email = 'priya.sharma@helpdesk.local';
\$u->password = bcrypt('Password123!');
\$u->role = 2;
\$u->save();
echo 'USER_ID:' . \$u->id;
")
PRIYA_ID=$(echo "$PRIYA_RESULT" | grep 'USER_ID:' | sed 's/USER_ID://' | tr -cd '0-9')
echo "Priya Sharma ID: $PRIYA_ID"

if [ -z "$PRIYA_ID" ]; then
    echo "ERROR: Failed to create Priya Sharma user"
    exit 1
fi

# Give Priya access to IT Support mailbox
fs_tinker "
\$user = \\App\\User::find($PRIYA_ID);
\$user->mailboxes()->syncWithoutDetaching([$MAILBOX_ID]);
" > /dev/null 2>&1

# Create customer David Kim
CUSTOMER_RESULT=$(fs_tinker "
\$existing = \\App\\Customer::whereHas('emails', function(\$q) { \$q->where('email', 'david.kim@acmecorp.com'); })->first();
if (\$existing) { echo 'CUSTOMER_ID:' . \$existing->id; exit; }
\$c = new \\App\\Customer();
\$c->first_name = 'David';
\$c->last_name = 'Kim';
\$c->save();
\$e = new \\App\\Email();
\$e->customer_id = \$c->id;
\$e->email = 'david.kim@acmecorp.com';
\$e->save();
echo 'CUSTOMER_ID:' . \$c->id;
")
CUSTOMER_ID=$(echo "$CUSTOMER_RESULT" | grep 'CUSTOMER_ID:' | sed 's/CUSTOMER_ID://' | tr -cd '0-9')
echo "Customer David Kim ID: $CUSTOMER_ID"

if [ -z "$CUSTOMER_ID" ]; then
    echo "ERROR: Failed to create customer"
    exit 1
fi

# Create a CLOSED conversation assigned to Marcus
# Status 3 = Closed
CONV_RESULT=$(fs_tinker "
\$conv = new \\App\\Conversation();
\$conv->type = 1;
\$conv->subject = 'VPN connection drops intermittently after Windows update';
\$conv->mailbox_id = $MAILBOX_ID;
\$conv->status = 3;
\$conv->state = 2;
\$conv->source_type = 1;
\$conv->source_via = 2;
\$conv->user_id = $MARCUS_ID;
\$conv->customer_id = $CUSTOMER_ID;
\$conv->customer_email = 'david.kim@acmecorp.com';
\$conv->preview = 'Since the latest Windows update KB5034441, my VPN connection drops every 15-20 minutes requiring manual reconnection.';
\$conv->closed_at = now()->subDays(3);
\$conv->closed_by_user_id = 1;
\$conv->last_reply_at = now()->subDays(5);
\$conv->last_reply_from = 2;
\$conv->save();
// Move to Closed folder for this mailbox (Type 3 = Closed)
\$folder = \\App\\Folder::where('mailbox_id', $MAILBOX_ID)->where('type', 3)->first();
if (\$folder) {
    \$conv->folder_id = \$folder->id;
    \$conv->save();
    \$folder->updateCounters();
}
echo 'CONV_ID:' . \$conv->id;
echo 'CONV_NUMBER:' . \$conv->number;
")
CONV_ID=$(echo "$CONV_RESULT" | grep 'CONV_ID:' | sed 's/CONV_ID://' | tr -cd '0-9')
CONV_NUMBER=$(echo "$CONV_RESULT" | grep 'CONV_NUMBER:' | sed 's/CONV_NUMBER://' | tr -cd '0-9')
echo "Conversation ID: $CONV_ID, Number: #$CONV_NUMBER"

if [ -z "$CONV_ID" ]; then
    echo "ERROR: Failed to create conversation"
    exit 1
fi

# Add the original customer message thread
fs_tinker "
\$thread = new \\App\\Thread();
\$thread->conversation_id = $CONV_ID;
\$thread->type = 1;
\$thread->status = 3;
\$thread->state = 3;
\$thread->body = '<p>Hi Support Team,</p><p>Since the latest Windows update KB5034441, my VPN connection (Cisco AnyConnect) drops every 15-20 minutes. I have to manually reconnect each time. This is severely impacting my ability to work remotely.</p><p>I have already tried:</p><ul><li>Reinstalling the VPN client</li><li>Resetting network adapters</li><li>Disabling power management on the network adapter</li></ul><p>The issue started right after the Windows update was applied last Tuesday.</p><p>Thanks,<br>David Kim<br>Engineering Department</p>';
\$thread->source_type = 1;
\$thread->source_via = 2;
\$thread->first = true;
\$thread->customer_id = $CUSTOMER_ID;
\$thread->created_by_customer_id = $CUSTOMER_ID;
\$thread->created_at = now()->subDays(7);
\$thread->save();
\$conv = \\App\\Conversation::find($CONV_ID);
\$conv->threads_count = 1;
\$conv->save();
echo 'THREAD_CREATED';
" > /dev/null 2>&1

# Save task state for verification
echo "$CONV_ID" > /tmp/task_conv_id.txt
echo "$CONV_NUMBER" > /tmp/task_conv_number.txt
echo "$MARCUS_ID" > /tmp/task_marcus_id.txt
echo "$PRIYA_ID" > /tmp/task_priya_id.txt
echo "$MAILBOX_ID" > /tmp/task_mailbox_id.txt
echo "$CUSTOMER_ID" > /tmp/task_customer_id.txt

# Record initial conversation state for anti-gaming
INITIAL_STATUS=$(fs_query "SELECT status FROM conversations WHERE id = $CONV_ID" 2>/dev/null | tr -cd '0-9')
INITIAL_USER=$(fs_query "SELECT user_id FROM conversations WHERE id = $CONV_ID" 2>/dev/null | tr -cd '0-9')
echo "$INITIAL_STATUS" > /tmp/task_initial_status.txt
echo "$INITIAL_USER" > /tmp/task_initial_user_id.txt

echo "Initial status: $INITIAL_STATUS (3=Closed)"
echo "Initial assignee user_id: $INITIAL_USER (Marcus=$MARCUS_ID)"

# Restart Firefox pointed to FreeScout login
pkill -f firefox || true
sleep 3
su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/login' > /tmp/firefox.log 2>&1 &"
sleep 6

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|freescout"; then
        echo "Firefox window detected"
        break
    fi
    sleep 2
done

# Maximize Firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="