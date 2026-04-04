#!/bin/bash
set -e
echo "=== Setting up disable_user_account task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ===== Create/Reset the target user (Marcus Webb) via ORM =====
echo "Configuring target user Marcus Webb..."

# Check if user exists
EXISTING_ID=$(fs_query "SELECT id FROM users WHERE email = 'marcus.webb@helpdesk.local' LIMIT 1" 2>/dev/null)

if [ -n "$EXISTING_ID" ]; then
    echo "User exists (ID: $EXISTING_ID). Resetting status to Active (1)..."
    fs_query "UPDATE users SET status = 1 WHERE id = $EXISTING_ID" 2>/dev/null
else
    echo "Creating new user..."
    # Create via Tinker to ensure proper hashing and default values
    fs_tinker "
\$u = new \\App\\User();
\$u->first_name = 'Marcus';
\$u->last_name = 'Webb';
\$u->email = 'marcus.webb@helpdesk.local';
\$u->password = bcrypt('TempPass456!');
\$u->role = 2; // User role
\$u->status = 1; // Active
\$u->save();
echo 'USER_CREATED:' . \$u->id;
" > /dev/null
fi

# Verify user state for baseline
USER_DATA=$(fs_query "SELECT id, status FROM users WHERE email = 'marcus.webb@helpdesk.local' LIMIT 1" 2>/dev/null)
USER_ID=$(echo "$USER_DATA" | cut -f1)
INITIAL_STATUS=$(echo "$USER_DATA" | cut -f2)

echo "$USER_ID" > /tmp/target_user_id.txt
echo "$INITIAL_STATUS" > /tmp/initial_target_status.txt
echo "Target User: Marcus Webb (ID: $USER_ID, Status: $INITIAL_STATUS)"

# Record initial admin status (to ensure no self-lockout)
ADMIN_STATUS=$(fs_query "SELECT status FROM users WHERE email = 'admin@helpdesk.local' LIMIT 1" 2>/dev/null)
echo "$ADMIN_STATUS" > /tmp/initial_admin_status.txt

# Record total user count (to detect deletion vs disable)
INITIAL_COUNT=$(get_user_count)
echo "$INITIAL_COUNT" > /tmp/initial_user_count.txt

# ===== Ensure Firefox is ready =====
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox "http://localhost:8080/login" > /tmp/firefox.log 2>&1 &
    sleep 8
fi

# Wait for window
wait_for_window "firefox\|mozilla\|freescout" 30

# Focus and maximize
focus_firefox
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Navigate to login or dashboard
navigate_to_url "http://localhost:8080/login"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="