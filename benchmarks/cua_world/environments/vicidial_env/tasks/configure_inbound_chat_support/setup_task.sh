#!/bin/bash
set -e
echo "=== Setting up configure_inbound_chat_support task ==="

# Load shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial services are running
vicidial_ensure_running

# Wait for MySQL to be ready inside the container
echo "Waiting for database connection..."
for i in {1..30}; do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
        echo "Database ready."
        break
    fi
    sleep 2
done

# RESET STATE: Ensure 'allow_chats' is 0 and the target group does not exist
echo "Resetting environment state..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "UPDATE system_settings SET allow_chats='0';"
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_chat_groups WHERE group_id='TECHSUP';"

# Record initial state for verification (should be 0)
INITIAL_ALLOW_CHATS=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT allow_chats FROM system_settings LIMIT 1;")
echo "$INITIAL_ALLOW_CHATS" > /tmp/initial_allow_chats.txt
echo "Initial allow_chats setting: $INITIAL_ALLOW_CHATS"

# Start Firefox and navigate to Admin
# We use the standard admin URL. Basic Auth is handled by the user/agent or via URL injection if permitted.
# The environment setup often includes auto-login or provided credentials. 
# We'll launch to the login page/dashboard.

if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '${VICIDIAL_ADMIN_URL}' > /dev/null 2>&1 &"
    
    # Wait for window
    wait_for_window "Firefox" 30
    
    # Maximize and focus
    maximize_active_window
    focus_firefox
fi

# Dismiss any potential "restore session" dialogs
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="