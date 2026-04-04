#!/bin/bash
# pre_task: Set up the escalate_overdue_task
# Creates a complaint case and an overdue task attached to it

echo "=== Setting up escalate_overdue_task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

ensure_portforward
wait_for_arkcase

# 1. Create the parent Complaint Case
CASE_TITLE="Urgent Review - Legacy Systems Audit"
CASE_DETAILS="Audit of legacy system access logs revealed potential anomalies. Legal review required immediately."

echo "Creating Complaint Case..."
CASE_RESPONSE=$(arkcase_api POST "plugin/complaint" "{
    \"caseType\": \"GENERAL\",
    \"complaintTitle\": \"${CASE_TITLE}\",
    \"details\": \"${CASE_DETAILS}\",
    \"priority\": \"Medium\",
    \"status\": \"ACTIVE\"
}" 2>/dev/null || echo "")

# Extract Case ID and Number
CASE_ID=$(echo "$CASE_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null)
CASE_NUMBER=$(echo "$CASE_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('caseNumber', ''))" 2>/dev/null)

if [ -z "$CASE_ID" ]; then
    echo "ERROR: Failed to create case. API Response: $CASE_RESPONSE"
    # Fallback for manual testing if API fails (unlikely in verified env)
    CASE_NUMBER="COMP-MANUAL-SETUP"
    CASE_ID="UNKNOWN"
else
    echo "Created Case: $CASE_NUMBER ($CASE_ID)"
fi

# 2. Create the Overdue Task
# Calculate yesterday's date in YYYY-MM-DD format
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
TASK_TITLE="Initial Legal Review"

echo "Creating Overdue Task (Due: $YESTERDAY)..."
# Note: API endpoint for task creation often depends on implementation. 
# Attempting standard creation linked to parent object.
TASK_PAYLOAD=$(cat <<EOF
{
    "title": "$TASK_TITLE",
    "description": "Review case details for compliance.",
    "priority": "Medium",
    "dueDate": "${YESTERDAY}T17:00:00.000Z",
    "holderId": "$CASE_ID",
    "holderType": "COMPLAINT",
    "assignee": "generic-user"
}
EOF
)

# Try 'plugin/task' or 'api/v1/task' - utilizing task_utils wrapper
TASK_RESPONSE=$(arkcase_api POST "plugin/task" "$TASK_PAYLOAD" 2>/dev/null)
TASK_ID=$(echo "$TASK_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('id', ''))" 2>/dev/null)

if [ -n "$TASK_ID" ]; then
    echo "Created Task: $TASK_ID"
    # Save Task ID for verification export
    echo "$TASK_ID" > /tmp/target_task_id.txt
else
    echo "WARNING: Task creation via API might have failed. Agent may need to handle a case without the specific task pre-made."
    echo "Debug Response: $TASK_RESPONSE"
fi

# 3. Write info for the agent
mkdir -p /home/ga/Documents
echo "Case Number: $CASE_NUMBER" > /home/ga/Documents/escalation_info.txt
echo "Task: $TASK_TITLE" >> /home/ga/Documents/escalation_info.txt
chmod 644 /home/ga/Documents/escalation_info.txt

# 4. Prepare Browser (Login)
# Kill any existing Firefox and clean lock files
pkill -9 -f firefox 2>/dev/null || true
find /home/ga -name ".parentlock" -delete 2>/dev/null || true
find /home/ga -name "parent.lock" -delete 2>/dev/null || true

# Start Firefox
SNAP_PROFILE=$(find /home/ga/snap/firefox -name "prefs.js" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")
LOGIN_URL="https://localhost:9443/arkcase/login"

if [ -n "$SNAP_PROFILE" ]; then
    su - ga -c "DISPLAY=:1 firefox -profile '$SNAP_PROFILE' '$LOGIN_URL' &>/dev/null &" &
else
    su - ga -c "DISPLAY=:1 firefox '$LOGIN_URL' &>/dev/null &" &
fi
sleep 15

# Perform Auto-Login
auto_login_arkcase "https://localhost:9443/arkcase/#!/complaints"

# Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="