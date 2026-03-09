#!/bin/bash
# Setup script for Consolidate Duplicate Complaints task

echo "=== Setting up Consolidate Duplicate Complaints Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure ArkCase is ready
ensure_portforward
wait_for_arkcase

# 1. Create MASTER Case
echo "Creating Master Case..."
MASTER_PAYLOAD='{
    "caseType": "GENERAL",
    "complaintTitle": "Construction noise violation at 7am - Master Record",
    "details": "Residents reporting loud construction noise starting before 7am ordinance. Location: 100 Main St.",
    "priority": "Medium",
    "status": "ACTIVE"
}'
MASTER_RESPONSE=$(arkcase_api POST "plugin/complaint" "$MASTER_PAYLOAD")
MASTER_ID=$(echo "$MASTER_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('complaintId', ''))" 2>/dev/null)

if [ -z "$MASTER_ID" ]; then
    echo "ERROR: Failed to create Master Case"
    echo "Response: $MASTER_RESPONSE"
    exit 1
fi
echo "Master Case ID: $MASTER_ID"

# 2. Create DUPLICATE Case
echo "Creating Duplicate Case..."
# We use a unique description to verify it gets copied later
UNIQUE_DESC="Early morning jackhammering on 4th Street causing vibration damage. Reported by caller $(date +%s)."
DUPLICATE_PAYLOAD="{
    \"caseType\": \"GENERAL\",
    \"complaintTitle\": \"Noise Complaint - Jackhammering\",
    \"details\": \"$UNIQUE_DESC\",
    \"priority\": \"Low\",
    \"status\": \"ACTIVE\"
}"
DUPLICATE_RESPONSE=$(arkcase_api POST "plugin/complaint" "$DUPLICATE_PAYLOAD")
DUPLICATE_ID=$(echo "$DUPLICATE_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('complaintId', ''))" 2>/dev/null)

if [ -z "$DUPLICATE_ID" ]; then
    echo "ERROR: Failed to create Duplicate Case"
    exit 1
fi
echo "Duplicate Case ID: $DUPLICATE_ID"

# 3. Create Instructions File
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/duplicate_processing.txt << EOF
DUPLICATE PROCESSING INSTRUCTIONS
=================================

Please consolidate the following duplicate complaint:

DUPLICATE CASE:
ID: $DUPLICATE_ID
Title: Noise Complaint - Jackhammering

MASTER CASE:
ID: $MASTER_ID
Title: Construction noise violation at 7am - Master Record

INSTRUCTIONS:
1. Copy the description/details from the DUPLICATE case.
2. Add it as a Note to the MASTER case.
3. Link the two cases (Add Association/Reference).
4. Close the DUPLICATE case.
EOF

chown ga:ga /home/ga/Documents/duplicate_processing.txt

# Save IDs for verification
echo "$MASTER_ID" > /tmp/master_case_id.txt
echo "$DUPLICATE_ID" > /tmp/duplicate_case_id.txt
echo "$UNIQUE_DESC" > /tmp/expected_note_content.txt

# 4. Prepare Browser
echo "Launching Firefox..."
# Kill any existing Firefox
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox and login
ensure_firefox_on_arkcase "https://localhost:9443/arkcase/login"
auto_login_arkcase "https://localhost:9443/arkcase/#!/complaints"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="