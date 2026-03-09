#!/bin/bash
set -e
echo "=== Setting up schedule_case_meeting task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Generate dynamic meeting date (5 days from now)
# We use Python to ensure cross-platform date math compatibility if needed, though date command works usually.
TARGET_DATE=$(date -d "+5 days" +%Y-%m-%d)
TARGET_TIME="10:00 AM"

# Save details file for the agent
cat > /home/ga/meeting_details.txt << EOF
URGENT: CASE REVIEW SCHEDULING
==============================

Please schedule the Oversight Review Board meeting for the Internal Data Handling Violation case.

Required Date: ${TARGET_DATE}
Required Time: ${TARGET_TIME}
Duration: 1 Hour
EOF

chown ga:ga /home/ga/meeting_details.txt

# Store expected values for verification (hidden from agent)
echo "$TARGET_DATE" > /tmp/expected_date.txt
echo "10:00:00" > /tmp/expected_time.txt

# 2. Ensure ArkCase is ready
ensure_portforward
wait_for_arkcase

# 3. Create the specific Complaint Case via API
echo "Creating complaint case..."
CASE_TITLE="Internal Data Handling Violation - Case #8821"
CASE_DETAILS="Internal audit log #8821 indicates potential exfiltration of sensitive PII to an unauthorized external endpoint. Immediate legal review required."

# We construct a JSON payload. Note: ArkCase API structure might vary, 
# but we stick to the standard 'complaint' plugin structure used in previous examples.
PAYLOAD=$(cat <<EOF
{
    "caseType": "GENERAL",
    "complaintTitle": "$CASE_TITLE",
    "details": "$CASE_DETAILS",
    "priority": "High",
    "status": "ACTIVE"
}
EOF
)

RESPONSE=$(arkcase_api POST "plugin/complaint" "$PAYLOAD")
echo "API Response: $RESPONSE"

# Extract Case ID for verification later
CASE_ID=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('complaintId', ''))" 2>/dev/null || echo "")

if [ -z "$CASE_ID" ]; then
    echo "WARNING: Failed to extract Complaint ID from API response. Verification may be limited."
else
    echo "Created Case ID: $CASE_ID"
    echo "$CASE_ID" > /tmp/target_case_id.txt
fi

# 4. Launch Firefox and Login
# Kill any existing Firefox
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox
ensure_firefox_on_arkcase "https://localhost:9443/arkcase/login"
maximize_firefox

# Auto-login
auto_login_arkcase "https://localhost:9443/arkcase/home.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="