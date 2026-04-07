#!/bin/bash
echo "=== Setting up Batch Tagging Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure connectivity
ensure_portforward
wait_for_arkcase

# Setup Firefox (kill existing, prepare profile)
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Log in and navigate to Dashboard
# We use the auto_login helper but stop at home to let agent initiate search
# Launch Firefox first
ensure_firefox_on_arkcase "${ARKCASE_URL}/home.html"
# Auto-login handles the typing and clicking
auto_login_arkcase "${ARKCASE_URL}/home.html"

echo "=== Creating Project Omega Cases ==="

# Define cases to create
# Format: Title|Priority|Description
CASES=(
    "Project Omega: Server Breach|High|Critical unauthorized access detected in sector 7 server farm. Immediate lockdown required."
    "Project Omega: Data Corruption|High|Database integrity check failed for customer records. Potential ransomware signature."
    "Project Omega: Routine Maintenance|Low|Scheduled downtime for patch application. No incidents reported."
)

IDS_FILE="/home/ga/.hidden_case_ids"
echo "" > "$IDS_FILE"
chmod 600 "$IDS_FILE" 2>/dev/null || true

# Counter for unique IDs
count=0

for case_info in "${CASES[@]}"; do
    IFS="|" read -r title priority details <<< "$case_info"
    
    echo "Creating case: $title ($priority)..."
    
    # Create via API
    # Note: Using complaintTitle maps to the visible Title field
    RESPONSE=$(curl -sk -X POST \
        -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "{
            \"caseType\": \"GENERAL\",
            \"complaintTitle\": \"$title\",
            \"details\": \"$details\",
            \"priority\": \"$priority\",
            \"status\": \"ACTIVE\"
        }" \
        "${ARKCASE_URL}/api/v1/plugin/complaint")
    
    # Extract ID using python for reliability
    CASE_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('complaintId', d.get('id', '')))" 2>/dev/null || true)
    
    if [ -n "$CASE_ID" ]; then
        echo "Created ID: $CASE_ID"
        # Save format: ID|Priority|Title
        echo "$CASE_ID|$priority|$title" >> "$IDS_FILE"
    else
        echo "ERROR: Failed to create case $title"
        echo "Response: $RESPONSE"
    fi
    sleep 2
done

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Agent is on Dashboard. Cases created."