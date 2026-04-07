#!/bin/bash
echo "=== Setting up search_case_record task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Verify Casebox is running
if ! wait_for_http "$CASEBOX_BASE_URL" 600; then
  echo "ERROR: Casebox is not reachable at $CASEBOX_BASE_URL"
  exit 1
fi

# Verify the target case exists in the database
BBW_ID=$(casebox_folder_by_name "Big Brother Watch")
if [ -z "$BBW_ID" ] || [ "$BBW_ID" = "NULL" ]; then
  log "WARNING: Could not find 'Big Brother Watch' case in database"
else
  log "Big Brother Watch case ID: $BBW_ID"
  echo "$BBW_ID" > /tmp/target_case_id
fi

# Open Firefox to Casebox
if ! ensure_casebox_logged_in "$CASEBOX_BASE_URL"; then
  echo "ERROR: Failed to open Casebox in Firefox"
  exit 1
fi

focus_firefox || true
sleep 2

take_screenshot /tmp/task_start.png
log "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="
