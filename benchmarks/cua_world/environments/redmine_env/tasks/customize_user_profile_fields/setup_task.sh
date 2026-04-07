#!/bin/bash
set -e
echo "=== Setting up customize_user_profile_fields task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Redmine is running
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

# We want to start at the Administration page to save the agent one click/navigation step,
# or just logged in. Let's start at the Administration panel as verified in the description context.
TARGET_URL="$REDMINE_BASE_URL/admin"

log "Opening Firefox at: $TARGET_URL"

# Use the helper to log in and navigate
if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in to Redmine and open target page."
  exit 1
fi

focus_firefox || true
sleep 2

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="