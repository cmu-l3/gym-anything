#!/bin/bash
set -euo pipefail
echo "=== Setting up configure_workflow_field_constraints task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification if needed)
date +%s > /tmp/task_start_time.txt

# Ensure Redmine is ready
wait_for_http "$REDMINE_BASE_URL/login" 60

# We want the agent to start logged in as admin at the Administration page
# This saves them the trivial step of logging in, focusing on the configuration task
TARGET_URL="$REDMINE_BASE_URL/admin"

log "Ensuring admin login and navigating to $TARGET_URL"
if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in to Redmine"
  exit 1
fi

# Ensure window is focused and maximized
focus_firefox || true
sleep 1

# Dismiss any potential "Close Firefox" dialogs
dismiss_close_firefox_dialog

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="