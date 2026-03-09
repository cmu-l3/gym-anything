#!/bin/bash
set -e
echo "=== Setting up merge_duplicate_customers task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure a mailbox exists (needed to create conversations)
MAILBOX_ID=$(ensure_mailbox_exists "Support" "support@helpdesk.local")
echo "Using Mailbox ID: $MAILBOX_ID"

# 1. Create Target Customer (Work) via ORM
echo "Creating Target Customer (Work)..."
TARGET_ID=$(fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = 'Elena';
\$c->last_name = 'Fisher';
\$c->notes = 'Primary work profile';
\$c->save();
\$e = new \\App\\Email();
\$e->customer_id = \$c->id;
\$e->email = 'elena.fisher@arch-design.co';
\$e->type = 'work';
\$e->save();
echo 'ID:' . \$c->id;
" | grep 'ID:' | sed 's/ID://' | tr -cd '0-9')

# Create a conversation for Target
create_conversation_via_orm "Project specs for Q4" "$MAILBOX_ID" "elena.fisher@arch-design.co" "$TARGET_ID" "Here are the specifications we discussed." > /dev/null

# 2. Create Source Customer (Personal) via ORM
echo "Creating Source Customer (Personal)..."
SOURCE_ID=$(fs_tinker "
\$c = new \\App\\Customer();
\$c->first_name = 'Elena';
\$c->last_name = 'Fisher';
\$c->notes = 'Duplicate profile created from gmail';
\$c->save();
\$e = new \\App\\Email();
\$e->customer_id = \$c->id;
\$e->email = 'elena.f@gmail.com';
\$e->type = 'home';
\$e->save();
echo 'ID:' . \$c->id;
" | grep 'ID:' | sed 's/ID://' | tr -cd '0-9')

# Create a conversation for Source
create_conversation_via_orm "Forgot my password" "$MAILBOX_ID" "elena.f@gmail.com" "$SOURCE_ID" "I cannot log in to the portal." > /dev/null

echo "Created Profiles - Target: $TARGET_ID, Source: $SOURCE_ID"

# Save IDs for verification
cat > /tmp/merge_setup_info.json << EOF
{
    "target_id": "$TARGET_ID",
    "source_id": "$SOURCE_ID",
    "target_email": "elena.fisher@arch-design.co",
    "source_email": "elena.f@gmail.com"
}
EOF

# Record initial customer count
INITIAL_COUNT=$(get_customer_count)
echo "$INITIAL_COUNT" > /tmp/initial_customer_count

# Clear cache to ensure new customers appear
docker exec freescout-app php /www/html/artisan cache:clear 2>/dev/null || true

# Start Firefox and navigate to Customers page
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/customers' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Wait for window and maximize
wait_for_window "firefox|mozilla|freescout" 30
focus_firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Navigate to Customers page specifically
navigate_to_url "http://localhost:8080/customers"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="