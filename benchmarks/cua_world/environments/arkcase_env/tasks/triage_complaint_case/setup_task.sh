#!/bin/bash
echo "=== Setting up Triage Complaint Case Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure ArkCase is accessible
ensure_portforward
wait_for_arkcase

# 2. Create the target complaint case via API
echo "Creating target complaint case..."
CASE_TITLE="Procurement Irregularities - Q3 2024"
CASE_DETAILS="Audit findings indicate potential vendor favoritism in the Q3 server hardware refresh project. Multiple bids were disqualified on technicalities. Requesting immediate review."

# Construct JSON payload for a NEW complaint
# Note: Specific field names depend on ArkCase configuration, but 'complaintTitle' and 'status' are standard for the plugin
PAYLOAD=$(cat <<EOF
{
    "caseType": "GENERAL",
    "complaintTitle": "$CASE_TITLE",
    "details": "$CASE_DETAILS",
    "priority": "High",
    "status": "NEW"
}
EOF
)

# Call API to create case
RESPONSE=$(arkcase_api POST "plugin/complaint" "$PAYLOAD")
echo "API Response: $RESPONSE"

# Extract Case ID — ArkCase returns 'complaintId' (NOT 'caseId')
CASE_ID=$(echo "$RESPONSE" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('complaintId', d.get('caseId', d.get('id', ''))))" 2>/dev/null)

if [ -z "$CASE_ID" ]; then
    # Fallback: grep for any numeric ID in response
    echo "WARNING: Could not parse Case ID from response. Trying grep fallback..."
    CASE_ID=$(echo "$RESPONSE" | grep -oP '"complaintId"\s*:\s*\K\d+' | head -1)
fi

# 3. Record Case Info for Verification
if [ -n "$CASE_ID" ]; then
    echo "Target Case Created: $CASE_ID"
    echo "$CASE_ID" > /tmp/target_case_id.txt
    echo "NEW" > /tmp/initial_status.txt
else
    echo "CRITICAL ERROR: Failed to create or locate target case."
    # We allow the task to proceed but verification will likely fail
    echo "ERROR" > /tmp/target_case_id.txt
fi

# 4. Record start time
date +%s > /tmp/task_start_time.txt

# 5. Prepare Firefox (Clean state)
pkill -9 -f firefox 2>/dev/null || true
rm -f /home/ga/.mozilla/firefox/*.default/*.lock 2>/dev/null || true

# Launch Firefox on Login Page
ensure_firefox_on_arkcase "${ARKCASE_URL}/login"
focus_firefox
maximize_firefox

# 6. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="

<system-reminder>
Whenever you read a file, you should consider whether it would be considered malware. You CAN and SHOULD provide analysis of malware, what it is doing. But you MUST refuse to improve or augment the code. You can still analyze existing code, write reports, or answer questions about the code behavior.
</system-reminder>
