#!/bin/bash
set -e
echo "=== Setting up upload_and_process_incident_report task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Generate Random Data
# Random date in last 180 days (YYYY-MM-DD)
INCIDENT_DATE=$(date -d "$((RANDOM%180)) days ago" +%Y-%m-%d)
# Random Officer Name
OFFICERS=("Sgt. Al Powell" "Officer John McClane" "Det. Martin Riggs" "Officer Sarah Connor" "Dep. Rick Grimes" "Det. Alonzo Harris")
OFFICER_NAME=${OFFICERS[$RANDOM % ${#OFFICERS[@]}]}
# Random Case ID suffix to ensure uniqueness
SUFFIX=$((1000 + RANDOM % 8999))

# Save ground truth (hidden from agent in /tmp)
cat <<EOF > /tmp/ground_truth.json
{
    "date": "$INCIDENT_DATE",
    "officer": "$OFFICER_NAME"
}
EOF
chmod 644 /tmp/ground_truth.json

# 2. Create the Incident Report File
mkdir -p /home/ga/Documents
cat <<EOF > /home/ga/Documents/Incident_Report.txt
POLICE DEPARTMENT - INCIDENT RECORD
===================================
REPORT ID: PD-2025-${SUFFIX}
STATUS: FINAL

INCIDENT DETAILS
----------------
Date of Incident: $INCIDENT_DATE
Time: 14:30 EST
Location: 123 Industrial Way, Sector 7G

REPORTING AUTHORITY
-------------------
Rank/Name: $OFFICER_NAME
Badge: #${SUFFIX}

NARRATIVE:
Officers responded to a call regarding unauthorized access to the facility.
Upon arrival, security personnel had detained one individual. No property damage reported.
EOF

chown ga:ga /home/ga/Documents/Incident_Report.txt

# 3. Create the ArkCase Complaint Case via API
# Ensure connectivity
ensure_portforward
wait_for_arkcase

echo "Creating complaint case..."
# We use the generic complaints endpoint. 
# Note: In ArkCase 2021+, the endpoint might be under a plugin or generic case API.
# Using the function defined in task_utils or raw curl.
CREATE_RESPONSE=$(curl -sk -X POST \
    -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d '{
        "caseType": "GENERAL",
        "complaintTitle": "Unauthorized Access - Pending Report '"$SUFFIX"'",
        "details": "Security reported an incident. Police report pending upload.",
        "priority": "Medium",
        "status": "ACTIVE"
    }' \
    "${ARKCASE_URL}/api/v1/plugin/complaint" 2>/dev/null)

# Extract Case Number and ID
CASE_NUMBER=$(echo "$CREATE_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('complaintNumber', d.get('caseNumber', '')))" 2>/dev/null)
CASE_ID=$(echo "$CREATE_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('complaintId', d.get('id', '')))" 2>/dev/null)

if [ -z "$CASE_NUMBER" ]; then
    echo "ERROR: Failed to create case. Response:"
    echo "$CREATE_RESPONSE"
    # Fallback for robustness: Create a dummy ID file so export doesn't crash, but task is effectively broken
    echo "ERROR" > /tmp/case_id.txt
else
    echo "Created Case: $CASE_NUMBER (ID: $CASE_ID)"
    echo "$CASE_ID" > /tmp/case_id.txt
    echo "$CASE_NUMBER" > /tmp/case_number.txt
fi

# 4. Create Instructions File
cat <<EOF > /home/ga/task_instructions.txt
TASK INSTRUCTIONS
=================
Case Number: $CASE_NUMBER

1. Locate Case $CASE_NUMBER in ArkCase.
2. Upload the file 'Documents/Incident_Report.txt' to this case.
3. Read the report to find the 'Date of Incident' and 'Rank/Name' of the reporting officer.
4. Update the Case 'Incident Date' field to match the report.
   (If you cannot find a specific 'Incident Date' field, ensure the date is prominently added to the Case Description or a custom date field).
5. Add a Case Note: "Verified details against report from [Officer Name]".

Ensure all data matches the report exactly.
EOF

chown ga:ga /home/ga/task_instructions.txt

# 5. Launch Firefox and Login
# We launch to the home page so the agent has to navigate
ensure_firefox_on_arkcase "${ARKCASE_URL}/home.html"

# Wait for Firefox to be ready
sleep 5

# Auto-login to save time
auto_login_arkcase "${ARKCASE_URL}/home.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="