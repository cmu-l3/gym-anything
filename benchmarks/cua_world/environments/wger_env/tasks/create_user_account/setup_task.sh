#!/bin/bash
echo "=== Setting up create_user_account task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming checks)
date +%s > /tmp/task_start_time.txt

# Record initial user count
INITIAL_COUNT=$(db_query "SELECT COUNT(*) FROM auth_user;" 2>/dev/null | xargs || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_user_count.txt

# Ensure wger is running and healthy
wait_for_wger_page

# Launch Firefox to the wger login page
launch_firefox_to "http://localhost/en/user/login" 8

# Automate login as admin to place the agent in the right state
echo "Automating login..."
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key Tab"
sleep 0.3
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool type --clearmodifiers 'admin'"
sleep 0.3
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key Tab"
sleep 0.3
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool type --clearmodifiers 'adminadmin'"
sleep 0.3
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key Return"
sleep 5

# Navigate to the wger dashboard
navigate_to "http://localhost/en/dashboard" 5

# Maximize the browser window for the agent
maximize_firefox
sleep 2

# Take initial screenshot showing the ready state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="