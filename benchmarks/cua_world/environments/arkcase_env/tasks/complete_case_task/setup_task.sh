#!/bin/bash
set -e
echo "=== Setting up complete_case_task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

source /workspace/scripts/task_utils.sh

# ── 1. Ensure ArkCase is accessible ──────────────────────────────────────────
ensure_portforward
wait_for_arkcase

# ── 2. Create a complaint case via REST API ──────────────────────────────────
echo "Creating complaint case..."
CASE_TITLE="Unauthorized Network Access - Incident Report IR-2024-3391"
CASE_DETAILS="On 2024-11-12, the security operations center detected anomalous network traffic originating from an internal workstation (IP 10.0.14.87). Preliminary analysis suggests a phishing email was the initial vector."

# Create Case
CASE_RESPONSE=$(curl -sk -X POST \
    -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{
        \"caseType\": \"GENERAL\",
        \"complaintTitle\": \"${CASE_TITLE}\",
        \"details\": \"${CASE_DETAILS}\",
        \"priority\": \"High\",
        \"status\": \"ACTIVE\"
    }" \
    "${ARKCASE_URL}/api/v1/plugin/complaint" 2>/dev/null)

# Extract case ID
CASE_ID=$(echo "$CASE_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Try multiple possible ID fields
    print(data.get('complaintId', data.get('id', data.get('objectId', ''))))
except: pass
" 2>/dev/null)

if [ -z "$CASE_ID" ]; then
    echo "WARNING: Failed to extract Case ID. Response: $CASE_RESPONSE"
    # Attempt to find it if it already exists
    SEARCH_RESP=$(curl -sk -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" "${ARKCASE_URL}/api/v1/plugin/complaint?limit=50" 2>/dev/null)
    CASE_ID=$(echo "$SEARCH_RESP" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    items = data.get('items', []) if isinstance(data, dict) else data
    for item in items:
        if 'IR-2024-3391' in item.get('complaintTitle', ''):
            print(item.get('complaintId', item.get('id', '')))
            break
except: pass
" 2>/dev/null)
fi

echo "Complaint Case ID: $CASE_ID"
echo "$CASE_ID" > /tmp/case_id.txt

# ── 3. Create a task on the case via REST API ────────────────────────────────
if [ -n "$CASE_ID" ]; then
    echo "Creating task on case $CASE_ID..."
    TASK_TITLE="Review Supporting Documentation for Evidence"
    TASK_DETAILS="Review all uploaded documents related to the network access incident."
    
    # Create Task
    TASK_RESPONSE=$(curl -sk -X POST \
        -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "{
            \"parentObjectType\": \"COMPLAINT\",
            \"parentObjectId\": ${CASE_ID},
            \"title\": \"${TASK_TITLE}\",
            \"assignee\": \"arkcase-admin@dev.arkcase.com\",
            \"status\": \"ACTIVE\",
            \"priority\": \"High\",
            \"details\": \"${TASK_DETAILS}\",
            \"taskStartDate\": \"$(date -I)T09:00:00.000Z\",
            \"dueDate\": \"$(date -d '+30 days' -I)T17:00:00.000Z\"
        }" \
        "${ARKCASE_URL}/api/v1/plugin/task" 2>/dev/null)

    # Extract Task ID
    TASK_ID=$(echo "$TASK_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('taskId', data.get('id', data.get('objectId', ''))))
except: pass
" 2>/dev/null)

    echo "Task ID: $TASK_ID"
    echo "$TASK_ID" > /tmp/task_id.txt
else
    echo "ERROR: Could not create case, skipping task creation."
fi

# ── 4. Open Firefox on ArkCase login page ────────────────────────────────────
echo "Opening Firefox..."
pkill -f firefox 2>/dev/null || true

# Start Firefox
ensure_firefox_on_arkcase "https://localhost:9443/arkcase/login"
sleep 5

# Maximize Firefox
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="