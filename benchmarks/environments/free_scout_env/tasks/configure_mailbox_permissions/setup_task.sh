#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up configure_mailbox_permissions task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# ===== Create the Field Service mailbox =====
echo "Creating Field Service mailbox..."
MAILBOX_ID=$(ensure_mailbox_exists "Field Service" "fieldservice@helpdesk.local")
echo "Mailbox ID: $MAILBOX_ID"
echo "$MAILBOX_ID" > /tmp/task_mailbox_id.txt

# ===== Create user: Sarah Chen =====
echo "Creating user Sarah Chen..."
SARAH_EXISTS=$(fs_query "SELECT id FROM users WHERE email='tech_sarah@helpdesk.local' LIMIT 1" 2>/dev/null)
if [ -z "$SARAH_EXISTS" ]; then
    SARAH_RESULT=$(fs_tinker "
\$u = new \App\User();
\$u->first_name = 'Sarah';
\$u->last_name = 'Chen';
\$u->email = 'tech_sarah@helpdesk.local';
\$u->password = bcrypt('TechPass123!');
\$u->role = 2; // User role
\$u->save();
echo 'USER_ID:' . \$u->id;
")
    SARAH_ID=$(echo "$SARAH_RESULT" | grep 'USER_ID:' | sed 's/USER_ID://' | tr -cd '0-9')
else
    SARAH_ID="$SARAH_EXISTS"
fi
echo "Sarah Chen user ID: $SARAH_ID"
echo "$SARAH_ID" > /tmp/task_sarah_id.txt

# ===== Create user: Marcus Rivera =====
echo "Creating user Marcus Rivera..."
MARCUS_EXISTS=$(fs_query "SELECT id FROM users WHERE email='tech_marcus@helpdesk.local' LIMIT 1" 2>/dev/null)
if [ -z "$MARCUS_EXISTS" ]; then
    MARCUS_RESULT=$(fs_tinker "
\$u = new \App\User();
\$u->first_name = 'Marcus';
\$u->last_name = 'Rivera';
\$u->email = 'tech_marcus@helpdesk.local';
\$u->password = bcrypt('TechPass123!');
\$u->role = 2; // User role
\$u->save();
echo 'USER_ID:' . \$u->id;
")
    MARCUS_ID=$(echo "$MARCUS_RESULT" | grep 'USER_ID:' | sed 's/USER_ID://' | tr -cd '0-9')
else
    MARCUS_ID="$MARCUS_EXISTS"
fi
echo "Marcus Rivera user ID: $MARCUS_ID"
echo "$MARCUS_ID" > /tmp/task_marcus_id.txt

# ===== Ensure NEITHER user has mailbox access initially =====
echo "Clearing any existing mailbox access..."
fs_query "DELETE FROM mailbox_user WHERE mailbox_id = $MAILBOX_ID AND user_id IN ($SARAH_ID, $MARCUS_ID)" 2>/dev/null || true

# ===== Record initial state =====
INITIAL_SARAH_ACCESS=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE mailbox_id = $MAILBOX_ID AND user_id = $SARAH_ID" 2>/dev/null || echo "0")
INITIAL_MARCUS_ACCESS=$(fs_query "SELECT COUNT(*) FROM mailbox_user WHERE mailbox_id = $MAILBOX_ID AND user_id = $MARCUS_ID" 2>/dev/null || echo "0")

# Save initial state to JSON for export script to use later
cat > /tmp/initial_state.json << EOF
{
    "sarah_access": ${INITIAL_SARAH_ACCESS:-0},
    "marcus_access": ${INITIAL_MARCUS_ACCESS:-0}
}
EOF

# ===== Ensure Firefox is open and ready =====
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/login' > /tmp/firefox.log 2>&1 &"
    sleep 8
fi

wait_for_window "firefox\|Mozilla\|FreeScout" 30 || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_firefox

# Take screenshot of initial state
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="