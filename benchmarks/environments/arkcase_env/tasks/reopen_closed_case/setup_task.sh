#!/bin/bash
set -e
echo "=== Setting up reopen_closed_case task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure port-forward is active and ArkCase is reachable
ensure_portforward
wait_for_arkcase

echo "=== Creating complaint case to be closed and then reopened ==="

# Define Case Data
CASE_TITLE="Public Records Request - Historical Budget Data"
CASE_DETAILS="Requester seeks all budget documents and expenditure reports from fiscal years 2020-2023 for the Department of Public Works. Request includes line-item details, contractor payments, and internal memos related to budget allocations."

# Step 1: Create a complaint case via API
# We use curl directly to handle the JSON response parsing
CREATE_RESPONSE=$(curl -sk -X POST \
    -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{
        \"caseType\": \"GENERAL\",
        \"complaintTitle\": \"${CASE_TITLE}\",
        \"details\": \"${CASE_DETAILS}\",
        \"priority\": \"Medium\"
    }" \
    "${ARKCASE_URL}/api/v1/plugin/complaint" 2>/dev/null)

echo "Create response received."

# Extract case ID and case number using python
# Handle potential varied response structure
CASE_INFO=$(echo "$CREATE_RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # ID might be complaintId, id, or objectId
    c_id = d.get('complaintId', d.get('id', d.get('objectId', '')))
    # Number might be complaintNumber, caseNumber
    c_num = d.get('complaintNumber', d.get('caseNumber', ''))
    print(f'{c_id}|{c_num}')
except Exception as e:
    print('|')
")

CASE_ID=$(echo "$CASE_INFO" | cut -d'|' -f1)
CASE_NUMBER=$(echo "$CASE_INFO" | cut -d'|' -f2)

if [ -z "$CASE_ID" ]; then
    echo "ERROR: Failed to create complaint case. Response:"
    echo "$CREATE_RESPONSE"
    # Fallback to a dummy ID to prevent script crash, though task will likely fail
    CASE_ID="dummy_id"
fi

echo "Created Case ID: $CASE_ID"
echo "Created Case Number: $CASE_NUMBER"

# Save for agent and export
echo "$CASE_ID" > /tmp/reopen_case_id.txt
echo "$CASE_NUMBER" > /tmp/reopen_case_number.txt

# Step 2: Close the case via API
echo "Closing the complaint case..."
sleep 2

CLOSE_DATE=$(date -u +%Y-%m-%dT%H:%M:%S.000+0000)
# Try specific close endpoint first
CLOSE_RESPONSE=$(curl -sk -X POST \
    -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{\"status\": \"CLOSED\", \"disposition\": \"Denied\", \"closeDate\": \"${CLOSE_DATE}\"}" \
    "${ARKCASE_URL}/api/v1/plugin/complaint/${CASE_ID}/close" 2>/dev/null)

# Verify closure or try PUT fallback
CURRENT_STATUS_JSON=$(curl -sk -X GET \
    -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
    -H "Accept: application/json" \
    "${ARKCASE_URL}/api/v1/plugin/complaint/${CASE_ID}" 2>/dev/null)

INITIAL_STATUS=$(echo "$CURRENT_STATUS_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")

if [ "$INITIAL_STATUS" != "CLOSED" ]; then
    echo "Close endpoint failed (Status: $INITIAL_STATUS), trying PUT update..."
    # Construct update payload
    UPDATE_PAYLOAD=$(echo "$CURRENT_STATUS_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
d['status'] = 'CLOSED'
d['disposition'] = 'Denied'
print(json.dumps(d))
")
    curl -sk -X PUT \
        -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "$UPDATE_PAYLOAD" \
        "${ARKCASE_URL}/api/v1/plugin/complaint/${CASE_ID}" > /dev/null
fi

# Record Initial State
echo "CLOSED" > /tmp/initial_case_status.txt
INITIAL_NOTE_COUNT=$(curl -sk -X GET \
    -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
    -H "Accept: application/json" \
    "${ARKCASE_URL}/api/v1/plugin/complaint/${CASE_ID}/notes" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d, list) else 0)" 2>/dev/null || echo "0")
echo "$INITIAL_NOTE_COUNT" > /tmp/initial_note_count.txt

echo "Initial Status: CLOSED"
echo "Initial Note Count: $INITIAL_NOTE_COUNT"

# Step 3: Prepare Browser
echo "Launching Firefox..."
# Direct navigation to the specific case to save search time
TARGET_URL="${ARKCASE_URL}/home.html#!/complaints/${CASE_ID}"

# Clean up any existing firefox
pkill -f firefox || true

ensure_firefox_on_arkcase "$TARGET_URL"
handle_ssl_warning
auto_login_arkcase "$TARGET_URL"

# Display info on screen for the agent (using xterm or just text file)
# We'll just rely on the description, but writing to a file helps
cat > /home/ga/Desktop/CASE_INFO.txt << EOF
Case Number: $CASE_NUMBER
Action Required: Reopen Case and Add Note
EOF

# Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="