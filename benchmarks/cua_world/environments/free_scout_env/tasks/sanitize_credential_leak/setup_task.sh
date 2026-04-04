#!/bin/bash
set -e
echo "=== Setting up sanitize_credential_leak task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure FreeScout is ready
for i in {1..30}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/login 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        break
    fi
    sleep 5
done

# 1. Create DevOps Mailbox
MAILBOX_ID=$(ensure_mailbox_exists "DevOps Support" "devops@helpdesk.local")
echo "Mailbox ID: $MAILBOX_ID"

# 2. Create a Junior Engineer User (who made the mistake)
USER_ID=$(fs_query "SELECT id FROM users WHERE email='junior.dev@helpdesk.local' LIMIT 1" 2>/dev/null)
if [ -z "$USER_ID" ]; then
    fs_tinker "
\$u = new \\App\\User();
\$u->first_name = 'Junior';
\$u->last_name = 'Dev';
\$u->email = 'junior.dev@helpdesk.local';
\$u->password = bcrypt('password');
\$u->role = 2;
\$u->status = 1;
\$u->save();
" > /dev/null
    USER_ID=$(find_user_by_email "junior.dev@helpdesk.local" | awk '{print $1}')
fi
echo "Junior Dev User ID: $USER_ID"

# 3. Create the Conversation
CONV_ID=$(create_conversation_via_orm "Production DB Latency" "$MAILBOX_ID" "monitoring@internal.local")
echo "Conversation ID: $CONV_ID"

# 4. Add the Note with the Secret (Simulating the leak)
# We use tinker to insert a 'note' type thread (type=2)
# The user_id is set to the Junior Dev
SECRET_BODY="I checked the logs and the application is using this connection string:<br><br>postgres://admin:ProductionPass2024!@10.0.0.5:5432/prod<br><br>It seems correct, so it might be a network issue."

# Escape quotes for PHP string
ESCAPED_BODY=$(echo "$SECRET_BODY" | sed "s/'/\\\\'/g")

THREAD_ID=$(fs_tinker "
\$t = new \\App\\Thread();
\$t->conversation_id = $CONV_ID;
\$t->type = 2; // Note
\$t->status = 1; // Active
\$t->state = 2; // Published
\$t->created_by_user_id = $USER_ID;
\$t->user_id = $USER_ID;
\$t->body = '$ESCAPED_BODY';
\$t->source_type = 1; // Web
\$t->save();
echo 'THREAD_ID:' . \$t->id;
" | grep 'THREAD_ID:' | sed 's/THREAD_ID://' | tr -cd '0-9')

echo "Leak Thread ID: $THREAD_ID"
echo "$THREAD_ID" > /tmp/target_thread_id.txt

# Update conversation preview and timestamps so it shows at top
fs_tinker "
\$c = \\App\\Conversation::find($CONV_ID);
\$c->updated_at = now();
\$c->save();
" > /dev/null

# 5. Launch Firefox
if ! pgrep -f "firefox" > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/mailbox/$MAILBOX_ID' > /dev/null 2>&1 &"
    sleep 10
fi

# Wait for window
wait_for_window "firefox\|mozilla\|freescout" 30

# Maximize Firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="