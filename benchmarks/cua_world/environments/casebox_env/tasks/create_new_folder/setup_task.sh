#!/bin/bash
echo "=== Setting up create_new_folder task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Verify Casebox is running
if ! wait_for_http "$CASEBOX_BASE_URL" 600; then
  echo "ERROR: Casebox is not reachable at $CASEBOX_BASE_URL"
  exit 1
fi

# Record initial folder count for verification
INITIAL_FOLDER_COUNT=$(casebox_query "SELECT COUNT(*) FROM tree WHERE dstatus=0" 2>/dev/null || echo "0")
echo "$INITIAL_FOLDER_COUNT" > /tmp/initial_tree_count
log "Initial tree node count: $INITIAL_FOLDER_COUNT"

# Verify the Active Investigations folder exists
ACTIVE_ID=$(casebox_folder_by_name "Active Investigations")
if [ -z "$ACTIVE_ID" ] || [ "$ACTIVE_ID" = "NULL" ]; then
  log "WARNING: Could not find 'Active Investigations' folder in database"
else
  log "Active Investigations folder ID: $ACTIVE_ID"
fi

# Open Firefox to Casebox login page
if ! ensure_casebox_logged_in "$CASEBOX_BASE_URL"; then
  echo "ERROR: Failed to open Casebox in Firefox"
  exit 1
fi

focus_firefox || true
sleep 2

take_screenshot /tmp/task_start.png
log "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="
