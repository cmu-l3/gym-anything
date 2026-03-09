#!/bin/bash
set -e
echo "=== Setting up Add Internal Follower Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create Users via Tinker to ensure proper hashing and defaults
echo "Creating users..."

# Sarah Chen (Analyst)
SARAH_ID=$(fs_tinker "
\$u = \\App\\User::where('email', 'sarah.chen@helpdesk.local')->first();
if (!\$u) {
    \$u = new \\App\\User();
    \$u->first_name = 'Sarah';
    \$u->last_name = 'Chen';
    \$u->email = 'sarah.chen@helpdesk.local';
    \$u->password = bcrypt('Analyst123!');
    \$u->role = 'user';
    \$u->status = 1;
    \$u->save();
}
echo 'USER_ID:' . \$u->id;
" | grep 'USER_ID:' | sed 's/USER_ID://' | tr -cd '0-9')

# Marcus Reynolds (Manager)
MARCUS_ID=$(fs_tinker "
\$u = \\App\\User::where('email', 'marcus.reynolds@helpdesk.local')->first();
if (!\$u) {
    \$u = new \\App\\User();
    \$u->first_name = 'Marcus';
    \$u->last_name = 'Reynolds';
    \$u->email = 'marcus.reynolds@helpdesk.local';
    \$u->password = bcrypt('Manager123!');
    \$u->role = 'admin'; // Admin to ensure he can be added easily
    \$u->status = 1;
    \$u->save();
}
echo 'USER_ID:' . \$u->id;
" | grep 'USER_ID:' | sed 's/USER_ID://' | tr -cd '0-9')

# 2. Create Mailbox
echo "Creating Security Operations mailbox..."
MAILBOX_ID=$(ensure_mailbox_exists "Security Operations" "security@helpdesk.local")

# Assign users to mailbox so they appear in lists
fs_tinker "
\$m = \\App\\Mailbox::find($MAILBOX_ID);
\$sarah = \\App\\User::find($SARAH_ID);
\$marcus = \\App\\User::find($MARCUS_ID);
// Sync users to mailbox (ID 1 is usually default admin, keep them too)
\$m->users()->syncWithoutDetaching([$SARAH_ID, $MARCUS_ID, 1]);
" > /dev/null

# 3. Create Conversation
echo "Creating critical security ticket..."
CONV_SUBJECT="Potential Data Exfiltration detected on server DB-01"
CONV_BODY="CRITICAL ALERT: Anomaly detection system flagged 45GB outbound traffic to IP 192.0.2.45 via port 443. Process owner: unknown. Immediate investigation required."

# Check if conversation exists to avoid duplicates on retry
EXISTING_CONV=$(find_conversation_by_subject "$CONV_SUBJECT")

if [ -n "$EXISTING_CONV" ]; then
    CONV_ID=$(echo "$EXISTING_CONV" | cut -f1)
    echo "Using existing conversation ID: $CONV_ID"
else
    CONV_ID=$(create_conversation_via_orm "$CONV_SUBJECT" "$MAILBOX_ID" "alert@monitoring.system" "" "$CONV_BODY")
    echo "Created new conversation ID: $CONV_ID"
fi

# 4. Set Initial State (Assign to Sarah, Ensure Marcus NOT following)
echo "Setting initial state..."
fs_tinker "
\$c = \\App\\Conversation::find($CONV_ID);
\$c->user_id = $SARAH_ID;
\$c->status = 1; // Active
\$c->save();

// Clear any existing followers for this convo
DB::table('conversation_user')->where('conversation_id', $CONV_ID)->delete();
" > /dev/null

# Save IDs for export script
echo "$CONV_ID" > /tmp/task_conv_id.txt
echo "$SARAH_ID" > /tmp/task_sarah_id.txt
echo "$MARCUS_ID" > /tmp/task_marcus_id.txt
echo "$MAILBOX_ID" > /tmp/task_mailbox_id.txt

# 5. Launch Application
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox "http://localhost:8080/mailbox/$MAILBOX_ID" > /tmp/firefox.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox|mozilla|freescout" 30
focus_firefox
navigate_to_url "http://localhost:8080/mailbox/$MAILBOX_ID"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="