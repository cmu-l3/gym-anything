#!/bin/bash
set -e
echo "=== Setting up task: configure_system_branding_localization ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Redmine is ready
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

# Reset global settings to defaults via Rails runner
# This ensures a clean state and prevents "already correct" gaming
echo "Resetting Redmine settings to defaults..."
docker exec -e SECRET_KEY_BASE="redmine_env_secret_key_base_do_not_use_in_production_xyz123" redmine \
  bundle exec rails runner "
    Setting.app_title = 'Redmine'
    Setting.welcome_text = 'Welcome to the Redmine project management system.'
    Setting.date_format = ''
    Setting.time_format = ''
    Setting.user_format = :firstname_lastname
  "

# Log in as admin and navigate to Administration panel
# We start at /admin so the agent is close to the goal but still needs to navigate tabs
TARGET_URL="$REDMINE_BASE_URL/admin"
log "Opening Firefox at: $TARGET_URL"

if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in to Redmine and open target page."
  exit 1
fi

# Focus and maximize
focus_firefox || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png
log "Task initial screenshot captured"

echo "=== Task setup complete ==="