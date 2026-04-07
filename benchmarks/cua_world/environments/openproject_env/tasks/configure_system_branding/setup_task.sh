#!/bin/bash
set -e
echo "=== Setting up task: configure_system_branding@1 ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OpenProject to be ready
wait_for_openproject

# Reset settings to default before task starts (to ensure we detect changes)
echo "Resetting configuration to defaults..."
docker exec openproject bash -c "cd /app && bundle exec rails runner \"
  Setting.app_title = 'OpenProject'
  Setting.welcome_text = 'Welcome to OpenProject'
  Setting.date_format = ''
  Setting.start_of_week = '7' # Sunday
\"" 2>/dev/null || echo "Warning: Failed to reset settings via rails runner"

# Launch Firefox to login page
echo "Launching Firefox..."
launch_firefox_to "http://localhost:8080/login" 8

# Automate Login
echo "Logging in as admin..."
# Focus Firefox
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
sleep 1

# Type username
DISPLAY=:1 xdotool type "admin"
sleep 0.5
DISPLAY=:1 xdotool key Tab
sleep 0.5

# Type password
DISPLAY=:1 xdotool type "Admin1234!"
sleep 0.5
DISPLAY=:1 xdotool key Return

# Wait for login to complete (redirect to home/mypage)
sleep 8

# Verify we are logged in by checking window title or just trusting the flow
# Maximize for the agent
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="