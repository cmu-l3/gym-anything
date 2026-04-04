#!/bin/bash
echo "=== Setting up change_timezone task ==="

source /workspace/scripts/task_utils.sh

# Remove any root-owned tmp files from previous runs that would block writes
sudo rm -f /tmp/task_start_timestamp /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Reset timezone to UTC (default state) so agent must actually change it
log "Resetting timezone to NA (default state)..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "
  UPDATE user_details SET time_zone = 'NA' WHERE email = '${ADMIN_EMAIL}'
" 2>/dev/null || \
mysql -u root "$DB_NAME" -e "
  UPDATE user_details SET time_zone = 'NA' WHERE email = '${ADMIN_EMAIL}'
" 2>/dev/null || true

# Wait for Socioboard to be ready
if ! wait_for_http "http://localhost/" 120; then
  echo "ERROR: Socioboard not reachable"
  exit 1
fi

# Clear any existing session by navigating to logout first
log "Clearing browser session via logout..."
open_socioboard_page "http://localhost/logout"
sleep 2

# Open Socioboard login page (agent will see login form)
navigate_to "http://localhost/login"
sleep 3

take_screenshot /tmp/task_start.png
log "Task start screenshot saved: /tmp/task_start.png"
echo "=== Task setup complete: change_timezone ==="
