#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up create_wiki_embedded_dashboard task ==="

# Record start time
date +%s > /tmp/task_start_time.txt

# Wait for OpenProject to be ready
wait_for_openproject

# Launch Firefox
# We start at the login page to ensure a clean session, but we'll help the agent by pre-filling or just setting the stage.
# The task description gives credentials, so landing on login is fine.
launch_firefox_to "http://localhost:8080/login" 5

# Attempt to automate login to match 'Starting State: logged in' requirement if possible,
# otherwise the agent has credentials. To be robust, we'll try to log in.
echo "Attempting auto-login..."
# Focus username field
DISPLAY=:1 xdotool key Tab
sleep 0.5
DISPLAY=:1 xdotool type "admin"
DISPLAY=:1 xdotool key Tab
sleep 0.5
DISPLAY=:1 xdotool type "Admin1234!"
DISPLAY=:1 xdotool key Return
sleep 5

# Navigate to the target project's wiki to save the agent some navigation steps
navigate_to "http://localhost:8080/projects/devops-automation/wiki" 5

# Maximize window
maximize_firefox

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="