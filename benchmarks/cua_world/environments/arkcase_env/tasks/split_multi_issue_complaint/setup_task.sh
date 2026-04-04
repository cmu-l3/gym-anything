#!/bin/bash
echo "=== Setting up Split Multi-Issue Complaint Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure ArkCase is accessible
ensure_portforward
wait_for_arkcase

# 2. Generate unique date for the task instance
TASK_DATE=$(date +%Y-%m-%d)
TASK_ID="CASE-$(date +%s)"

# 3. Create the "Kitchen Sink" complaint via API
echo "Creating initial multi-issue complaint..."
COMPLAINT_TITLE="Neighbor Nuisance Report - $TASK_DATE"
COMPLAINT_DESC="The resident at 42 Oak St plays drums loudly every night after 11 PM. Also, there is a large pile of rotting trash in his driveway that has been there for weeks and is attracting rats."

# Using the helper from task_utils.sh or raw curl
# We need to capture the ID to track it later
RESPONSE=$(arkcase_api POST "plugin/complaint" "{
    \"caseType\": \"GENERAL\",
    \"complaintTitle\": \"$COMPLAINT_TITLE\",
    \"details\": \"$COMPLAINT_DESC\",
    \"priority\": \"Medium\",
    \"status\": \"ACTIVE\"
}" 2>/dev/null)

# Extract Case ID (Complaint Number)
ORIGINAL_CASE_NUMBER=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('caseNumber', ''))" 2>/dev/null)
ORIGINAL_CASE_ID=$(echo "$RESPONSE" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('complaintId', d.get('id', '')))" 2>/dev/null)

if [ -z "$ORIGINAL_CASE_NUMBER" ]; then
    echo "ERROR: Failed to create initial case."
    echo "API Response: $RESPONSE"
    # Fallback for manual creation if API fails (unlikely if env is healthy)
    exit 1
fi

echo "Created Case: $ORIGINAL_CASE_NUMBER (ID: $ORIGINAL_CASE_ID)"

# Save ID for verification
echo "$ORIGINAL_CASE_ID" > /tmp/original_case_id.txt
echo "$ORIGINAL_CASE_NUMBER" > /tmp/original_case_number.txt
date +%s > /tmp/task_start_time.txt

# 4. Launch Firefox and Login
# Kill any existing Firefox
pkill -9 -f firefox 2>/dev/null || true
sleep 2

ensure_firefox_on_arkcase "https://localhost:9443/arkcase/login"

# Auto-login
auto_login_arkcase "https://localhost:9443/arkcase/#!/complaints"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Original Case: $COMPLAINT_TITLE"
echo "Case Number: $ORIGINAL_CASE_NUMBER"