#!/bin/bash
set -e
echo "=== Setting up add_request_tasks task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for SDP to be fully running
ensure_sdp_running

# Clear mandatory password change (if any)
clear_mandatory_password_change

# Write Python login script helper
write_python_login_script

# Get or generate API key
API_KEY=$(get_sdp_api_key_from_db)
if [ -z "$API_KEY" ] || [ ${#API_KEY} -lt 20 ]; then
    log "Generating API key via web login..."
    generate_api_key_via_web
    sleep 3
    API_KEY=$(get_sdp_api_key_from_db)
fi

echo "$API_KEY" > /tmp/sdp_api_key.txt
log "API Key setup complete"

# =====================================================
# Create the parent request via REST API
# =====================================================
REQUEST_TITLE="New Employee IT Onboarding - John Martinez"
REQUEST_DESC="Complete IT onboarding setup for new hire John Martinez, Software Engineering department. Start date: next Monday. Requires laptop provisioning, software installation, and network/email account setup. Manager: Sarah Chen. Cost center: ENG-2024."

log "Creating parent request: $REQUEST_TITLE"

# Construct JSON payload
INPUT_DATA=$(cat <<JSONEOF
{
    "request": {
        "subject": "${REQUEST_TITLE}",
        "description": "${REQUEST_DESC}",
        "priority": {
            "name": "High"
        },
        "status": {
            "name": "Open"
        },
        "request_type": {
            "name": "Service Request"
        }
    }
}
JSONEOF
)

# Send API request
RESPONSE=$(curl -sk -X POST \
    "${SDP_BASE_URL}/api/v3/requests" \
    -H "authtoken: ${API_KEY}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "input_data=${INPUT_DATA}" \
    2>/dev/null)

log "Request Creation Response: $(echo "$RESPONSE" | head -c 200)..."

# Verify request exists in DB and get ID
REQUEST_ID=$(sdp_db_exec "SELECT wo.WORKORDERID FROM workorder wo WHERE wo.TITLE = '${REQUEST_TITLE}' ORDER BY wo.WORKORDERID DESC LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

if [ -n "$REQUEST_ID" ] && [ "$REQUEST_ID" != "" ]; then
    log "Parent request created with ID: $REQUEST_ID"
    echo "$REQUEST_ID" > /tmp/parent_request_id.txt
else
    # Fallback: Try to find any existing one or insert manually (risky with complex schema, better to fail loud or try simpler API)
    log "ERROR: Could not verify request creation. Trying simpler fallback..."
    # Fallback to DB insert would be very complex due to multiple tables (workorder, workorderstates, etc).
    # Instead, we rely on the agent finding it if it exists, or the task failing setup.
    # We will try one more time to find partial match
    REQUEST_ID=$(sdp_db_exec "SELECT wo.WORKORDERID FROM workorder wo WHERE wo.TITLE LIKE '%John Martinez%' ORDER BY wo.WORKORDERID DESC LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
    echo "$REQUEST_ID" > /tmp/parent_request_id.txt
fi

# Store initial task count (should be 0)
INITIAL_TASK_COUNT=0
if [ -n "$REQUEST_ID" ]; then
    INITIAL_TASK_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM taskdetails td JOIN workordertotask wt ON td.TASKID = wt.TASKID WHERE wt.WORKORDERID = ${REQUEST_ID};" 2>/dev/null || echo "0")
fi
echo "${INITIAL_TASK_COUNT}" > /tmp/initial_task_count.txt

# =====================================================
# Launch Firefox on SDP
# =====================================================
log "Launching Firefox..."

# Kill existing Firefox
pkill -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox to the requests list
su - ga -c "DISPLAY=:1 firefox --no-remote 'https://localhost:8080/WOListView.do' &" 2>/dev/null
sleep 8

# Handle self-signed cert if needed
DISPLAY=:1 xdotool key --delay 500 Tab Tab Tab Tab Return 2>/dev/null || true
sleep 3
DISPLAY=:1 xdotool key Tab Return 2>/dev/null || true # Accept risk
sleep 5

# Maximize browser
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

log "=== Task setup complete ==="