#!/bin/bash
echo "=== Setting up soc_analyst_role_setup task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_timestamp

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Wait for REST API
echo "Waiting for Splunk REST API..."
for i in $(seq 1 30); do
    API_RESPONSE=$(curl -sk -u admin:SplunkAdmin1! https://localhost:8089/services/server/info 2>/dev/null || true)
    if echo "$API_RESPONSE" | grep -q "server_name"; then
        echo "Splunk REST API is ready"
        break
    fi
    sleep 2
done

# Ensure the role and user do NOT exist (clean slate)
echo "Cleaning up any existing artifacts..."
/opt/splunk/bin/splunk remove user jsmith -auth admin:SplunkAdmin1! 2>/dev/null || true
/opt/splunk/bin/splunk remove role junior_soc_analyst -auth admin:SplunkAdmin1! 2>/dev/null || true

# Check initial states via REST to prove they don't exist
ROLE_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" -u admin:SplunkAdmin1! \
    "https://localhost:8089/services/authorization/roles/junior_soc_analyst?output_mode=json" 2>/dev/null || echo "000")
USER_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" -u admin:SplunkAdmin1! \
    "https://localhost:8089/services/authentication/users/jsmith?output_mode=json" 2>/dev/null || echo "000")

echo "$ROLE_STATUS" > /tmp/initial_role_status
echo "$USER_STATUS" > /tmp/initial_user_status

echo "Initial Role HTTP Status: $ROLE_STATUS (Expected: 404)"
echo "Initial User HTTP Status: $USER_STATUS (Expected: 404)"

# CRITICAL: Ensure Firefox is running with Splunk visible BEFORE task starts
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    echo "Task setup FAILED - task start state is INVALID"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

# Navigate to Access Controls to set up the starting view
navigate_to_splunk_page "http://localhost:8000/en-US/manager/system/accesscontrols"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png
echo "Task start screenshot taken"

echo "=== Task setup complete ==="