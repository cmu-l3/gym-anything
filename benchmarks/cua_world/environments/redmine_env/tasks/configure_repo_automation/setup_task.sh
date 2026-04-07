#!/bin/bash
set -e
echo "=== Setting up configure_repo_automation task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Reset Repository Settings to a "bad" state so we can verify the agent actually changes them.
# We turn off time logging, clear keywords, and unset status/activity mappings.
echo "Resetting Redmine settings to defaults..."
docker exec redmine bundle exec rails runner "
  Setting.commit_fix_keywords = 'fixes'
  Setting.commit_fix_status_id = nil
  Setting.commit_fix_done_ratio = nil
  Setting.commit_logtime_enabled = 0
  Setting.commit_logtime_activity_id = nil
"

# 3. Ensure Redmine is ready
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

# 4. Log in and navigate to the Settings area to give the agent a fair start
TARGET_URL="$REDMINE_BASE_URL/settings"
log "Opening Firefox at: $TARGET_URL"

if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in to Redmine and open target page."
  exit 1
fi

focus_firefox || true
sleep 2

# 5. Capture initial state screenshot
take_screenshot /tmp/task_initial.png
log "Initial screenshot captured: /tmp/task_initial.png"

echo "=== Task setup complete ==="