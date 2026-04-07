#!/bin/bash
echo "=== Setting up edit_user_role task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. PREPARE DATA
# Ensure target user exists and is in the correct initial state (Supervisor = 0)
echo "Resetting target user state..."
opencad_db_query "UPDATE users SET supervisor_privilege = 0, approved = 1, admin_privilege = 1 WHERE email = 'dispatch@opencad.local';"

# 2. RECORD INITIAL STATE
# Record target user state
TARGET_INITIAL=$(opencad_db_query "SELECT id, admin_privilege, supervisor_privilege, approved FROM users WHERE email='dispatch@opencad.local'")
echo "$TARGET_INITIAL" > /tmp/target_initial_state.txt

# Record hash of all other users to detect side effects (anti-gaming)
# We concat ID + supervisor_privilege for all other users
OTHER_USERS_STATE=$(opencad_db_query "SELECT GROUP_CONCAT(CONCAT(id, ':', supervisor_privilege) ORDER BY id) FROM users WHERE email != 'dispatch@opencad.local'")
echo "$OTHER_USERS_STATE" > /tmp/other_users_initial_state.txt

echo "Initial Target State: $TARGET_INITIAL"
echo "Initial Others State Hash: $(echo "$OTHER_USERS_STATE" | md5sum)"

# 3. PREPARE APPLICATION
# Remove Firefox profile locks and relaunch to ensure clean state
rm -f /home/ga/.mozilla/firefox/default-release/lock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Start Firefox at login page
echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php' &"
sleep 10

# Dismiss Firefox popups/restore session dialogs
DISPLAY=:1 wmctrl -c "Make the Firefox" 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|OpenCAD" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# 4. CAPTURE EVIDENCE
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="