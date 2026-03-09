#!/bin/bash
set -e
echo "=== Setting up add_incident_location task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure port forwarding is active for API calls
ensure_portforward
wait_for_arkcase

# 1. Create the specific Complaint Case via API
# We create it programmatically to ensure a clean starting state
CASE_TITLE="HazMat-Spill-2024-001"
CASE_DETAILS="Report of chemical smell near the river. Caller observed discolored water."
echo "Creating complaint case: $CASE_TITLE..."

# Create case and capture the full response
# We use a python script to parse the ID reliably from the JSON response
API_RESPONSE=$(arkcase_api POST "plugin/complaint" "{
    \"caseType\": \"GENERAL\",
    \"complaintTitle\": \"$CASE_TITLE\",
    \"details\": \"$CASE_DETAILS\",
    \"priority\": \"High\",
    \"status\": \"ACTIVE\"
}")

# Extract Case ID
CASE_ID=$(echo "$API_RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # ID field can vary by version (id, caseId, complaintId)
    print(d.get('complaintId') or d.get('id') or d.get('caseId') or '')
except Exception as e:
    print('')
")

if [ -z "$CASE_ID" ]; then
    echo "ERROR: Failed to create case. API Response:"
    echo "$API_RESPONSE"
    # Fallback: Try to find if it already exists
    exit 1
fi

echo "Created Case ID: $CASE_ID"
echo "$CASE_ID" > /tmp/task_case_id.txt

# 2. Prepare instructions for the agent
INSTRUCTIONS_FILE="/home/ga/case_incident_info.txt"
cat > "$INSTRUCTIONS_FILE" <<EOF
INCIDENT REPORT DETAILS
-----------------------
Case Ref: $CASE_TITLE
Status: Investigation Open

ACTION REQUIRED:
Please log the specific incident location in the case file.

INCIDENT LOCATION:
Address: 2500 East Second Street
City: Reno
State: NV
Zip: 89595
Type: Incident Site

This is required for the jurisdiction map.
EOF
chown ga:ga "$INSTRUCTIONS_FILE"

# 3. Setup Firefox
# Kill existing instances
pkill -9 -f firefox 2>/dev/null || true
rm -f /home/ga/.mozilla/firefox/*.default-release/lock 2>/dev/null || true

# Launch Firefox and login
ensure_firefox_on_arkcase "${ARKCASE_URL}/home.html"
auto_login_arkcase "${ARKCASE_URL}/home.html"

# Open the instructions file for the agent to see
su - ga -c "DISPLAY=:1 xdg-open '$INSTRUCTIONS_FILE'"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="