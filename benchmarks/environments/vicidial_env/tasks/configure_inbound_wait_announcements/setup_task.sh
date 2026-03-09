#!/bin/bash
set -e

echo "=== Setting up Inbound Wait Announcements Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

echo "Configuring database state..."
# Wait for MySQL
for i in {1..30}; do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Create/Reset the TECH_SUPPORT Inbound Group with default/incorrect settings
# This ensures the agent must actually change them to pass.
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
INSERT IGNORE INTO vicidial_inbound_groups (group_id, group_name, active, group_color, next_agent_call, queue_priority) 
VALUES ('TECH_SUPPORT', 'Technical Support Queue', 'Y', 'blue', 'longest_wait_time', 0);

UPDATE vicidial_inbound_groups SET 
    calculate_hold_time='N',
    hold_time_option='NONE',
    hold_time_seconds=360,
    hold_time_minimum=0,
    periodic_announce='',
    periodic_announce_seconds=0
WHERE group_id='TECH_SUPPORT';
"

# Launch Firefox to the Admin Panel
# Using the standard admin URL
ADMIN_URL="${VICIDIAL_ADMIN_URL:-http://localhost/vicidial/admin.php}"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$ADMIN_URL' > /tmp/firefox.log 2>&1 &"
else
    echo "Firefox already running, navigating..."
    navigate_to_url "$ADMIN_URL"
fi

# Wait for window
wait_for_window "Firefox\|Mozilla\|Vicidial" 60

# Focus and maximize
focus_firefox
maximize_active_window

# Handle login if needed (Standard 6666/andromeda)
# The env setup might handle this, but adding redundancy here helps
sleep 3
if DISPLAY=:1 xdotool search --name "Authentication Required" >/dev/null 2>&1; then
    DISPLAY=:1 xdotool type "6666"
    DISPLAY=:1 xdotool key Tab
    DISPLAY=:1 xdotool type "andromeda"
    DISPLAY=:1 xdotool key Return
    sleep 3
fi

# Navigate to Inbound Groups screen to save agent one click (optional, but good for starting state)
navigate_to_url "${ADMIN_URL}?ADD=1000"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="