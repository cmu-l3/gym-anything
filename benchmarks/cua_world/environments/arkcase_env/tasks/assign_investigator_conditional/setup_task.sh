#!/bin/bash
echo "=== Setting up Conditional Investigator Assignment Task ==="

source /workspace/scripts/task_utils.sh

# 1. Establish Anti-Gaming Timestamp
date +%s > /tmp/task_start_time.txt

# 2. Wait for ArkCase availability
ensure_portforward
wait_for_arkcase

# 3. Determine Random Risk Level (0 = Low, 1 = High)
RISK_LEVEL=$((RANDOM % 2))
echo "$RISK_LEVEL" > /tmp/.task_risk_level
chmod 644 /tmp/.task_risk_level

if [ "$RISK_LEVEL" -eq 1 ]; then
    NOTE_CONTENT="WARNING: SUBJECT HAS HISTORY OF VIOLENCE. HIGH RISK. APPROACH WITH CAUTION."
    echo "Setup: Mode is HIGH RISK (Expect Nick Wilde)"
else
    NOTE_CONTENT="Subject has no prior criminal record. Cooperative and polite during previous encounters."
    echo "Setup: Mode is LOW RISK (Expect Judy Hopps)"
fi

# 4. Create Officers (Judy Hopps & Nick Wilde)
# Using generic person creation payload structure
echo "Creating Officer Judy Hopps..."
arkcase_api POST "service/people" '{
    "firstName": "Judy",
    "lastName": "Hopps",
    "title": "Officer",
    "personType": "Employee"
}' > /dev/null

echo "Creating Officer Nick Wilde..."
arkcase_api POST "service/people" '{
    "firstName": "Nick",
    "lastName": "Wilde",
    "title": "Special Response Officer",
    "personType": "Employee"
}' > /dev/null

# 5. Create Subject (Victor Vance) with Conditional Note
echo "Creating Subject Victor Vance..."
# We create the person first
SUBJECT_RESP=$(arkcase_api POST "service/people" "{
    \"firstName\": \"Victor\",
    \"lastName\": \"Vance\",
    \"notes\": \"$NOTE_CONTENT\"
}")

# 6. Create Complaint Case
echo "Creating Complaint Case..."
arkcase_api POST "plugin/complaint" '{
    "caseType": "GENERAL",
    "complaintTitle": "Disturbance at Central Plaza",
    "details": "Reports of a disturbance involving subject Victor Vance. Dispatch required immediately. Check subject profile before assigning response unit.",
    "priority": "High",
    "status": "ACTIVE"
}' > /tmp/case_creation.json

# Extract Case ID for verification later
CASE_ID=$(cat /tmp/case_creation.json | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null)
echo "$CASE_ID" > /tmp/target_case_id.txt
echo "Created Case ID: $CASE_ID"

# 7. Prepare Browser State
# Kill any existing Firefox
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox and Login
# Using auto_login_arkcase helper (assuming it handles launch + login)
# If not, we manually launch and login as per standard pattern
ensure_firefox_on_arkcase "https://localhost:9443/arkcase/login"
auto_login_arkcase "https://localhost:9443/arkcase/home.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="