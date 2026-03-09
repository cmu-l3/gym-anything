#!/bin/bash
set -e
echo "=== Setting up Skills-Based Routing Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Ensure Vicidial is running
vicidial_ensure_running

# 2. Reset Database to specific initial state (Anti-Gaming / Clean Slate)
echo "Resetting database state..."

# Reset AGENTDIRECT routing to 'longest_wait_time' (default)
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "UPDATE vicidial_inbound_groups SET next_agent_call='longest_wait_time' WHERE group_id='AGENTDIRECT';"

# Reset User 6666 rank for AGENTDIRECT to 0 (or remove entry if we want to be strict, but updating is safer for existing map)
# We ensure the user has access but rank is 0.
# First, ensure the mapping exists
count=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT count(*) FROM vicidial_inbound_group_agents WHERE user='6666' AND group_id='AGENTDIRECT';")
if [ "$count" -eq "0" ]; then
    docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
        "INSERT INTO vicidial_inbound_group_agents (user, group_id, group_rank, group_weight, calls_today) VALUES ('6666', 'AGENTDIRECT', '0', '0', '0');"
else
    docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
        "UPDATE vicidial_inbound_group_agents SET group_rank='0' WHERE user='6666' AND group_id='AGENTDIRECT';"
fi

# Record start timestamp
date +%s > /tmp/task_start_time.txt

# 3. Launch Firefox and Login
echo "Launching Firefox..."
# Kill any existing firefox
pkill -f firefox 2>/dev/null || true

# Admin URL
VICIDIAL_ADMIN_URL="http://localhost/vicidial/admin.php"

# Start Firefox
su - ga -c "DISPLAY=:1 firefox '$VICIDIAL_ADMIN_URL' > /tmp/firefox.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 30

# Focus and maximize
focus_firefox
maximize_active_window

# Handle Login
# Vicidial usually uses Basic Auth or Form Auth depending on setup. 
# The env setup suggests it might prompt. We try to type credentials just in case, 
# or assume the environment pre-auths. 
# Based on env description, we'll proactively type credentials if the title indicates login or generic firefox.
sleep 3
DISPLAY=:1 xdotool type "6666"
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type "andromeda"
DISPLAY=:1 xdotool key Return
sleep 3

# Navigate explicitly to ensure we are on the main admin screen
navigate_to_url "http://localhost/vicidial/admin.php"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="