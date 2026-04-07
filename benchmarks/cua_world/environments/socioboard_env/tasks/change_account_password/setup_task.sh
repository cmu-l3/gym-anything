#!/bin/bash
echo "=== Setting up change_account_password task ==="

source /workspace/scripts/task_utils.sh

# Cleanup previous state
sudo rm -f /tmp/task_start_time.txt /tmp/initial_pwd_hash.txt /tmp/password_change_done.txt /tmp/task_result.json /tmp/task_start.png 2>/dev/null || true

# Wait for Socioboard to be ready
if ! wait_for_http "http://localhost/" 120; then
  echo "ERROR: Socioboard not reachable"
  exit 1
fi

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Capture the initial password hash from MariaDB
log "Capturing initial password hash..."
mysql -u root socioboard -N -B -e "SELECT password FROM user_details WHERE email='admin@socioboard.local' LIMIT 1" > /tmp/initial_pwd_hash.txt 2>/dev/null || echo "" > /tmp/initial_pwd_hash.txt

# Clear any existing session by navigating to logout first
log "Clearing browser session via logout..."
open_socioboard_page "http://localhost/logout"
sleep 2

# Open Socioboard login page (agent will see login form)
navigate_to "http://localhost/login"
sleep 3

# Take initial state screenshot
take_screenshot /tmp/task_start.png
log "Task start screenshot saved: /tmp/task_start.png"

echo "=== Task setup complete: change_account_password ==="