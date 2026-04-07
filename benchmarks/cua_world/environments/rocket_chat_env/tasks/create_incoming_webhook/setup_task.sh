#!/bin/bash
set -euo pipefail

echo "=== Setting up create_incoming_webhook task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Rocket.Chat is running
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 120; then
    echo "ERROR: Rocket.Chat did not become ready."
    exit 1
fi

# Authenticate as admin to record initial state and clean up
LOGIN_JSON=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

TOKEN=$(echo "$LOGIN_JSON" | jq -r '.data.authToken // empty')
USERID=$(echo "$LOGIN_JSON" | jq -r '.data.userId // empty')

if [ -n "$TOKEN" ] && [ -n "$USERID" ]; then
    AUTH_H1="X-Auth-Token: $TOKEN"
    AUTH_H2="X-User-Id: $USERID"

    # 1. Clean up: Remove existing integration if it exists (to ensure fresh start)
    # We look for integrations with name "CI/CD Pipeline"
    EXISTING_ID=$(curl -sS -H "$AUTH_H1" -H "$AUTH_H2" \
        "${ROCKETCHAT_BASE_URL}/api/v1/integrations.list" | \
        jq -r '.integrations[] | select(.name == "CI/CD Pipeline") | ._id' 2>/dev/null || true)
    
    if [ -n "$EXISTING_ID" ]; then
        echo "Removing pre-existing integration: $EXISTING_ID"
        curl -sS -X POST -H "$AUTH_H1" -H "$AUTH_H2" \
            -H "Content-Type: application/json" \
            -d "{\"integrationId\":\"$EXISTING_ID\", \"type\":\"webhook-incoming\"}" \
            "${ROCKETCHAT_BASE_URL}/api/v1/integrations.remove" >/dev/null 2>&1 || true
    fi

    # 2. Record initial integration count
    INTEGRATION_COUNT=$(curl -sS -H "$AUTH_H1" -H "$AUTH_H2" \
        "${ROCKETCHAT_BASE_URL}/api/v1/integrations.list" | \
        jq '.integrations | length' 2>/dev/null || echo "0")
    echo "$INTEGRATION_COUNT" > /tmp/initial_integration_count.txt

    # 3. Record initial message count in target channel
    MSG_COUNT=$(curl -sS -H "$AUTH_H1" -H "$AUTH_H2" \
        "${ROCKETCHAT_BASE_URL}/api/v1/channels.history?roomName=release-updates&count=1" | \
        jq '.messages | length' 2>/dev/null || echo "0") # Just checking connectivity, count not critical for history API
    # Better to get total count if possible, but history is paged. 
    # We will rely on searching for the specific message text in export_result.sh, 
    # ensuring it's recent.
else
    echo "WARNING: Could not authenticate to set up initial state. Proceeding anyway."
    echo "0" > /tmp/initial_integration_count.txt
fi

# Clean up file system
rm -f /home/ga/webhook_url.txt

# Start Firefox
restart_firefox "${ROCKETCHAT_LOGIN_URL}"
sleep 5

# Maximize Firefox
focus_firefox || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="