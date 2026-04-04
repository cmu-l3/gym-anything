#!/bin/bash
echo "=== Setting up create_team task ==="

source /workspace/scripts/task_utils.sh

# Remove any root-owned tmp files from previous runs that would block writes
sudo rm -f /tmp/task_start_timestamp /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Remove any existing team with this name for clean start
log "Cleaning up existing 'Digital Marketing Hub' team if present..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "
  DELETE FROM team_informations WHERE team_name = 'Digital Marketing Hub'
" 2>/dev/null || \
mysql -u root "$DB_NAME" -e "
  DELETE FROM team_informations WHERE team_name = 'Digital Marketing Hub'
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
echo "=== Task setup complete: create_team ==="
