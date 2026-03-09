#!/bin/bash
set -e
echo "=== Setting up compile_investigation_report task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure ArkCase is accessible
ensure_portforward
wait_for_arkcase

echo "=== Generating Investigation Data ==="

# Initialize Ground Truth directory and file (hidden from agent in /root)
mkdir -p /root/validation
echo "[]" > /root/validation/ground_truth.json
chmod 700 /root/validation

# Helper function to create case and update ground truth
create_case_and_log() {
    local title="$1"
    local priority="$2"
    local is_target="$3"

    echo "Creating case: $title..."

    # Create complaint via API
    RESPONSE=$(curl -sk -X POST \
        -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "{
            \"caseType\": \"GENERAL\",
            \"complaintTitle\": \"$title\",
            \"details\": \"Automated entry for investigation task. Reference: $title\",
            \"priority\": \"$priority\",
            \"status\": \"ACTIVE\"
        }" \
        "${ARKCASE_URL}/api/v1/plugin/complaint")

    # Extract Case Number (Format usually COMP-YYYY-XXXX)
    # Using python for reliable JSON parsing
    CASE_NUM=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('caseNumber', d.get('complaintNumber', 'UNKNOWN')))" 2>/dev/null || echo "UNKNOWN")

    if [ "$CASE_NUM" == "UNKNOWN" ] || [ -z "$CASE_NUM" ]; then
        echo "WARNING: Failed to extract case number for '$title'"
    else
        echo "  -> Created: $CASE_NUM"

        # If it is a target case, append to ground truth JSON
        if [ "$is_target" == "true" ]; then
            python3 -c "
import sys, json, os
gt_file = '/root/validation/ground_truth.json'
try:
    with open(gt_file, 'r') as f:
        data = json.load(f)
    entry = {
        'caseNumber': '$CASE_NUM',
        'title': '$title',
        'priority': '$priority'
    }
    data.append(entry)
    with open(gt_file, 'w') as f:
        json.dump(data, f, indent=2)
except Exception as e:
    print(f'Error updating ground truth: {e}')
"
        fi
    fi
    sleep 1
}

# 1. Create Target Cases (The ones the agent must find)
create_case_and_log "Security Protocol Violation - Operation Nightshade" "High" "true"
create_case_and_log "Logistics Delay affecting Operation Nightshade" "Medium" "true"
create_case_and_log "Personnel Complaint: Operation Nightshade Shift Roster" "Low" "true"

# 2. Create Distractor Cases (The ones the agent must ignore)
create_case_and_log "Budget Review - Project Bluebook" "High" "false"
create_case_and_log "Facility Maintenance - Operation Daylight" "Low" "false"
create_case_and_log "General IT Support Request" "Medium" "false"

# Ensure Firefox is running
ensure_firefox_on_arkcase "${ARKCASE_URL}/home.html"

# Handle SSL and Login
handle_ssl_warning
auto_login_arkcase "${ARKCASE_URL}/home.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="