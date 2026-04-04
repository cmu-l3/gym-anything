#!/bin/bash
set -e
echo "=== Setting up generate_case_priority_report task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure ArkCase is ready
ensure_portforward
wait_for_arkcase

# 2. Generate Real Data (3 Complaint Cases)
# We will create 3 cases with distinct priorities and titles
echo "Generating test data..."

# Define cases: Title | Priority | Description
CASE_DATA=(
    "Environmental Impact Assessment - Project Alpha|High|Urgent review required for wetlands impact statement."
    "Budget Oversight Inquiry - Q3 2024|Medium|Discrepancy found in office supply procurement ledger."
    "Vendor Contract Dispute - Cleaning Services|Low|Vendor missed scheduled cleaning on Nov 12th."
)

GROUND_TRUTH_FILE="/tmp/ground_truth.json"
INPUT_LIST_FILE="/home/ga/priority_audit_list.txt"
rm -f "$GROUND_TRUTH_FILE" "$INPUT_LIST_FILE" "/home/ga/priority_report.csv"

# Start JSON array for ground truth
echo "[" > "$GROUND_TRUTH_FILE"

count=0
for entry in "${CASE_DATA[@]}"; do
    IFS="|" read -r title priority details <<< "$entry"
    
    echo "Creating case: $title ($priority)"
    
    # Create case via API
    # Note: ArkCase uses 'complaintTitle' for the title field
    RESPONSE=$(arkcase_api POST "plugin/complaint" "{
        \"caseType\": \"GENERAL\",
        \"complaintTitle\": \"$title\",
        \"details\": \"$details\",
        \"priority\": \"$priority\",
        \"status\": \"ACTIVE\"
    }")
    
    # Extract Case Number (complaintId) using jq
    # The API returns the full object
    CASE_NUM=$(echo "$RESPONSE" | jq -r '.complaintId // empty')
    
    if [ -z "$CASE_NUM" ]; then
        echo "ERROR: Failed to create case via API. Response: $RESPONSE"
        # Fallback to a fake number if API fails (shouldn't happen in healthy env)
        CASE_NUM="COMP-$(date +%s)-$count"
    fi
    
    echo "Created Case: $CASE_NUM"
    
    # Append to input list for the agent
    echo "$CASE_NUM" >> "$INPUT_LIST_FILE"
    
    # Append to ground truth JSON
    if [ "$count" -gt 0 ]; then echo "," >> "$GROUND_TRUTH_FILE"; fi
    cat <<EOF >> "$GROUND_TRUTH_FILE"
    {
        "case_number": "$CASE_NUM",
        "title": "$title",
        "priority": "$priority"
    }
EOF
    
    ((count++))
    sleep 2 # Slight delay to ensure processing
done

echo "]" >> "$GROUND_TRUTH_FILE"
chmod 644 "$GROUND_TRUTH_FILE"
chown ga:ga "$INPUT_LIST_FILE"

# 3. Setup Browser
# Kill any existing Firefox and clean lock files
pkill -9 -f firefox 2>/dev/null || true
sleep 2
find /home/ga -name ".parentlock" -delete 2>/dev/null || true
find /home/ga -name "parent.lock" -delete 2>/dev/null || true

# Launch Firefox on ArkCase login page
echo "Launching Firefox..."
ensure_firefox_on_arkcase "https://localhost:9443/arkcase/login"
focus_firefox
maximize_firefox

# 4. Auto-login
auto_login_arkcase "https://localhost:9443/arkcase/home.html"

# 5. Record Start Time & Screenshot
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Input file created: $INPUT_LIST_FILE"
cat "$INPUT_LIST_FILE"