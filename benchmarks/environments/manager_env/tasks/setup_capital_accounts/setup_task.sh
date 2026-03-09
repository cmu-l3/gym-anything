#!/bin/bash
# Setup script for setup_capital_accounts task

echo "=== Setting up setup_capital_accounts task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager is running
wait_for_manager 60

# Record task start time
date +%s > /tmp/task_start_time.txt

# Start Firefox at the Summary page (Dashboard)
# We do not use 'open_manager_at' with a module because the agent needs to 
# go to Settings first to enable the module.
echo "Opening Manager.io at Summary page..."

# Kill existing Firefox
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid firefox \
    -profile '/home/ga/.mozilla/firefox/manager.profile' \
    --new-window 'http://localhost:8080/' \
    > /tmp/firefox_task.log 2>&1 &"

# Wait for window and maximize
wait_for_window "Firefox" 30
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss any startup dialogs if they appear
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Verify Northwind Traders is loaded (navigate to it if needed)
# The default environment setup usually loads it, but we ensure we are in the business.
# We'll rely on the agent to select the business if not already selected, 
# but usually http://localhost:8080/ redirects to the last business.

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Setup Capital Accounts for Maria Chen ($50k) and David Chen ($75k)"