#!/bin/bash
set -e
echo "=== Setting up configure_incoming_email_integration task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OpenProject to be ready
wait_for_openproject

# Reset these settings to known bad state (disabled/empty) via Rails runner
# This ensures we aren't detecting previous successful runs or defaults that happen to match
echo "Resetting incoming email settings..."
op_rails "Setting.mail_handler_enable_incoming_emails = 0; Setting.mail_handler_api_key = ''; Setting.mail_handler_body_delimiters = '';"

# Launch Firefox
# We start at the login page. The agent is expected to log in.
launch_firefox_to "http://localhost:8080/login" 5

# Attempt to automate login for convenience, but if it fails, the agent has creds
echo "Automating login..."
navigate_to "http://localhost:8080/login" 2

# Type username
xdotool type "admin"
xdotool key Tab
sleep 0.5

# Type password
xdotool type "Admin1234!"
xdotool key Return
sleep 5

# Navigate to Administration overview to start
navigate_to "http://localhost:8080/admin" 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="