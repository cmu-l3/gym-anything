#!/bin/bash
set -euo pipefail
echo "=== Setting up create_custom_fields task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Redmine is reachable
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

# Get API key for verification and initial state check
API_KEY=$(redmine_admin_api_key)

# Record initial custom field count (anti-gaming baseline)
# We use the API to get the current state of custom fields
INITIAL_CF_JSON=$(curl -s -H "X-Redmine-API-Key: $API_KEY" "$REDMINE_BASE_URL/custom_fields.json")
INITIAL_COUNT=$(echo "$INITIAL_CF_JSON" | jq '[.custom_fields[] | select(.customized_type=="issue")] | length' 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_custom_field_count.txt
echo "Initial issue custom field count: $INITIAL_COUNT"

# Prepare the browser
# We start by logging in and navigating to the Custom Fields list to save the agent some navigation time,
# or we could just go to the home page. The prompt implies starting logged in.
TARGET_URL="$REDMINE_BASE_URL/custom_fields"

if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in to Redmine and open target page."
  exit 1
fi

# Ensure window is maximized and focused
focus_firefox || true
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="