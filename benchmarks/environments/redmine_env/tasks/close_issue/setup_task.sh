#!/bin/bash
echo "=== Setting up close_issue task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

ISSUE_ID=$(redmine_issue_id_by_subject "SSL certificate for api.devlabs.io expires")
if [ -z "$ISSUE_ID" ] || [ "$ISSUE_ID" = "null" ]; then
  echo "ERROR: Could not find issue 'SSL certificate for api.devlabs.io...' in seed result"
  exit 1
fi

log "Issue ID: $ISSUE_ID"
TARGET_URL=$(redmine_issue_url "$ISSUE_ID")
log "Opening Firefox at: $TARGET_URL"

if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in to Redmine and open target page."
  exit 1
fi

focus_firefox || true
sleep 2

take_screenshot /tmp/task_start.png
log "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="
