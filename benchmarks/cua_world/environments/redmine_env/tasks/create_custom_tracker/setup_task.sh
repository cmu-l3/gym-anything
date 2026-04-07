#!/bin/bash
echo "=== Setting up create_custom_tracker task ==="

source /workspace/scripts/task_utils.sh

# Anti-gaming: Record start time
date +%s > /tmp/task_start_time.txt

# Ensure Redmine is up
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

# Get Admin API Key for initial state recording
ADMIN_API_KEY=$(redmine_admin_api_key)
if [ -z "$ADMIN_API_KEY" ]; then
    echo "WARNING: Could not get Admin API key from seed result. verification might be limited."
else
    # Record initial tracker count
    curl -s -H "X-Redmine-API-Key: $ADMIN_API_KEY" "$REDMINE_BASE_URL/trackers.json" | jq '.trackers | length' > /tmp/initial_tracker_count.txt 2>/dev/null || echo "0" > /tmp/initial_tracker_count.txt
fi

# Target: Administration page
TARGET_URL="$REDMINE_BASE_URL/admin"

log "Opening Firefox at: $TARGET_URL"

# Login and navigate
if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in to Redmine and open target page."
  exit 1
fi

focus_firefox || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="