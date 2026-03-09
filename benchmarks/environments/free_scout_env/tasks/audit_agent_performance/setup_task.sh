#!/bin/bash
set -e
echo "=== Setting up Task: Audit Agent Performance ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure FreeScout is running and Mailbox exists
MAILBOX_ID=$(ensure_mailbox_exists "Support" "support@helpdesk.local")
echo "Using Mailbox ID: $MAILBOX_ID"

# 2. Create Agent Users
# We use fs_tinker to create users directly in the app logic
echo "Creating agents..."

# Marcus Chen (The target)
MARCUS_ID=$(fs_tinker "
\$u = \\App\\User::firstOrCreate(
    ['email' => 'marcus@helpdesk.local'],
    ['first_name' => 'Marcus', 'last_name' => 'Chen', 'password' => bcrypt('password123'), 'role' => 2]
);
echo 'ID:' . \$u->id;
" | grep 'ID:' | sed 's/ID://' | tr -cd '0-9')

# Sarah Connor (Distractor)
SARAH_ID=$(fs_tinker "
\$u = \\App\\User::firstOrCreate(
    ['email' => 'sarah@helpdesk.local'],
    ['first_name' => 'Sarah', 'last_name' => 'Connor', 'password' => bcrypt('password123'), 'role' => 2]
);
echo 'ID:' . \$u->id;
" | grep 'ID:' | sed 's/ID://' | tr -cd '0-9')

echo "Marcus ID: $MARCUS_ID"
echo "Sarah ID: $SARAH_ID"

# 3. Clean up existing conversations to ensure count is deterministic for this run
# (Optional, but helps keep the environment clean from previous runs)
fs_query "DELETE FROM conversations WHERE mailbox_id = $MAILBOX_ID" 2>/dev/null || true
fs_query "DELETE FROM threads WHERE conversation_id IN (SELECT id FROM conversations WHERE mailbox_id = $MAILBOX_ID)" 2>/dev/null || true

# 4. Generate Randomized Data
# Target count for Marcus (Closed) - Random between 4 and 12
TARGET_COUNT=$(( ( RANDOM % 9 ) + 4 ))

echo "Generating $TARGET_COUNT closed tickets for Marcus..."

# Helper to create ticket via ORM
create_ticket_orm() {
    local subject="$1"
    local user_id="$2"
    local status="$3" # 1=Active, 2=Pending, 3=Closed
    local customer_email="customer$RANDOM@example.com"
    
    # Using the helper from task_utils, but modifying slightly to accept explicit status/user
    # The helper 'create_conversation_via_orm' usually defaults to Active/Unassigned, 
    # so we'll do a custom tinker call here for speed and precision.
    fs_tinker "
    \$conv = new \\App\\Conversation();
    \$conv->type = 1;
    \$conv->mailbox_id = $MAILBOX_ID;
    \$conv->subject = '$subject';
    \$conv->status = $status;
    \$conv->state = 2; // Published
    \$conv->customer_email = '$customer_email';
    \$conv->customer_id = 1; 
    \$conv->user_id = $user_id;
    \$conv->save();
    // Create a thread so it looks real
    \$thread = new \\App\\Thread();
    \$thread->conversation_id = \$conv->id;
    \$thread->type = 1;
    \$thread->body = 'This is an automated test ticket body.';
    \$thread->created_by_customer_id = 1;
    \$thread->save();
    " > /dev/null
}

# Create Target Tickets (Marcus + Closed)
for i in $(seq 1 $TARGET_COUNT); do
    create_ticket_orm "Support Request #$RANDOM - Payment Issue" "$MARCUS_ID" "3"
done

# Create Distractor Tickets (Marcus + Active/Pending)
# These ensure the agent checks STATUS, not just assignee
for i in {1..5}; do
    create_ticket_orm "Ongoing Investigation #$RANDOM" "$MARCUS_ID" "1"
done
for i in {1..3}; do
    create_ticket_orm "Waiting for customer #$RANDOM" "$MARCUS_ID" "2"
done

# Create Distractor Tickets (Sarah + Closed/Active)
# These ensure the agent checks ASSIGNEE, not just status
for i in {1..7}; do
    create_ticket_orm "Feature Request #$RANDOM" "$SARAH_ID" "3"
done
for i in {1..4}; do
    create_ticket_orm "Bug Report #$RANDOM" "$SARAH_ID" "1"
done

# Create Unassigned Tickets
for i in {1..3}; do
    create_ticket_orm "New Inquiry #$RANDOM" "null" "1"
done

# 5. Clear Cache
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# 6. Launch Firefox
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/conversations' > /tmp/firefox.log 2>&1 &"
    sleep 8
fi

wait_for_window "firefox|mozilla|freescout" 30
focus_firefox
navigate_to_url "http://localhost:8080/conversations" 

# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete. Target Count: $TARGET_COUNT ==="