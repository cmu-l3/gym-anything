#!/bin/bash
set -e
echo "=== Setting up set_conversation_pending task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create the Mailbox
echo "Creating AV Field Service mailbox..."
MAILBOX_ID=$(ensure_mailbox_exists "AV Field Service" "avservice@helpdesk.local")
echo "Mailbox ID: $MAILBOX_ID"

# 2. Create Customers
echo "Creating customers..."
# Target customer
DAVID_ID=$(fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = 'David';
\$c->last_name = 'Chen';
\$c->save();
\$e = new \\App\\Email();
\$e->email = 'david.chen@meridianfinancial.com';
\$e->customer_id = \$c->id;
\$e->save();
echo 'ID:'.\$c->id;
" | grep 'ID:' | sed 's/ID://')

# Decoy customer
SARAH_ID=$(fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = 'Sarah';
\$c->last_name = 'Miller';
\$c->save();
\$e = new \\App\\Email();
\$e->email = 'sarah.m@meridianfinancial.com';
\$e->customer_id = \$c->id;
\$e->save();
echo 'ID:'.\$c->id;
" | grep 'ID:' | sed 's/ID://')

# 3. Create Target Conversation (Active/1)
echo "Creating target conversation..."
TARGET_BODY="Hi Support, The main display in Conference Room B is not showing any signal on screens 3 and 4. We tried reseating the HDMI cables but the distribution amp seems to be flashing red. We have a board meeting on Thursday."
TARGET_CONV_ID=$(create_conversation_via_orm \
  "Conference Room B Display - No Signal on Screens 3 and 4" \
  "$MAILBOX_ID" \
  "david.chen@meridianfinancial.com" \
  "$DAVID_ID" \
  "$TARGET_BODY")

# Explicitly set status to Active (1) just to be safe
fs_query "UPDATE conversations SET status = 1 WHERE id = $TARGET_CONV_ID"

echo "Target Conversation ID: $TARGET_CONV_ID"

# 4. Create Decoy Conversations
echo "Creating decoy conversations..."

# Decoy 1: Active
create_conversation_via_orm \
  "Lobby Digital Signage Player Offline" \
  "$MAILBOX_ID" \
  "sarah.m@meridianfinancial.com" \
  "$SARAH_ID" \
  "The brightsign player in the lobby is showing a black screen."

# Decoy 2: Active
create_conversation_via_orm \
  "Boardroom Crestron Panel Unresponsive" \
  "$MAILBOX_ID" \
  "david.chen@meridianfinancial.com" \
  "$DAVID_ID" \
  "Touch panel is frozen again."

# Decoy 3: Closed (Status 3)
CLOSED_ID=$(create_conversation_via_orm \
  "Annual Projector Lamp Replacement Schedule" \
  "$MAILBOX_ID" \
  "sarah.m@meridianfinancial.com" \
  "$SARAH_ID" \
  "Here is the schedule for next month.")
fs_query "UPDATE conversations SET status = 3 WHERE id = $CLOSED_ID"

# 5. Record state for verification
echo "$TARGET_CONV_ID" > /tmp/target_conversation_id.txt
# Verify initial status is 1
INITIAL_STATUS=$(fs_query "SELECT status FROM conversations WHERE id = $TARGET_CONV_ID" | tr -cd '0-9')
echo "$INITIAL_STATUS" > /tmp/initial_status.txt

echo "Target ID: $TARGET_CONV_ID, Initial Status: $INITIAL_STATUS"

# 6. Clear Cache
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# 7. Prepare Browser
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox "http://localhost:8080/mailbox/$MAILBOX_ID" > /tmp/firefox.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox|mozilla|freescout" 60
focus_firefox
navigate_to_url "http://localhost:8080/mailbox/$MAILBOX_ID"
sleep 5

# 8. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="