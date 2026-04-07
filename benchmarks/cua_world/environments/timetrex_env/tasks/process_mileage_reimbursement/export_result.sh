#!/bin/bash
# Export script for Process Mileage Reimbursement task

echo "=== Exporting Process Mileage Reimbursement Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback definitions
if ! type timetrex_query &>/dev/null; then
    timetrex_query() {
        docker exec timetrex-postgres psql -U timetrex -d timetrex -t -c "$1" 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
    }
fi

if ! type ensure_docker_containers &>/dev/null; then
    ensure_docker_containers() {
        if ! docker ps | grep -q timetrex-postgres; then
            docker start timetrex-postgres timetrex-app 2>/dev/null || true
            sleep 5
        fi
    }
fi

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Ensure DB is accessible
ensure_docker_containers

# 2. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 3. Read task start time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 4. Query Database for Expected Configuration (Policy)
echo "Looking for 'Mileage Reimbursement' policy..."
POLICY_ID=$(timetrex_query "SELECT id FROM expense_policy WHERE name='Mileage Reimbursement' AND deleted=0 ORDER BY created_date DESC LIMIT 1;")

POLICY_FOUND="false"
if [ -n "$POLICY_ID" ]; then
    POLICY_FOUND="true"
    echo "Found Policy ID: $POLICY_ID"
else
    echo "Policy not found."
fi

# 5. Query Database for Expected Transaction (Expense for John Doe created AFTER task start)
echo "Looking for new expenses for John Doe..."
JOHN_ID=$(timetrex_query "SELECT id FROM users WHERE first_name='John' AND last_name='Doe' AND deleted=0 LIMIT 1;")

EXPENSE_FOUND="false"
EXPENSE_ID=""
EXPENSE_AMOUNT="0"
EXPENSE_DATE=""
EXPENSE_POLICY_ID=""
EXPENSE_DESC=""

if [ -n "$JOHN_ID" ]; then
    # Look for the most recently created expense for John Doe since the task started
    EXPENSE_ID=$(timetrex_query "SELECT id FROM user_expense WHERE user_id='$JOHN_ID' AND deleted=0 AND created_date >= $TASK_START ORDER BY created_date DESC LIMIT 1;")
    
    if [ -n "$EXPENSE_ID" ]; then
        EXPENSE_FOUND="true"
        EXPENSE_AMOUNT=$(timetrex_query "SELECT amount FROM user_expense WHERE id='$EXPENSE_ID';")
        EXPENSE_DATE=$(timetrex_query "SELECT date_stamp::text FROM user_expense WHERE id='$EXPENSE_ID';")
        EXPENSE_POLICY_ID=$(timetrex_query "SELECT expense_policy_id FROM user_expense WHERE id='$EXPENSE_ID';")
        EXPENSE_DESC=$(timetrex_query "SELECT description FROM user_expense WHERE id='$EXPENSE_ID';")
        
        echo "Found Expense ID: $EXPENSE_ID, Amount: $EXPENSE_AMOUNT, Date: $EXPENSE_DATE"
    else
        echo "No new expense records found for John Doe."
    fi
else
    echo "ERROR: John Doe user ID not found."
fi

# Clean descriptions for JSON
EXPENSE_DESC_ESC=$(echo "$EXPENSE_DESC" | sed 's/"/\\"/g' | sed 's/\n/\\n/g')

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/reimbursement_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "export_timestamp": $(date +%s),
    "policy_found": $POLICY_FOUND,
    "policy_id": "$POLICY_ID",
    "expense_found": $EXPENSE_FOUND,
    "expense_id": "$EXPENSE_ID",
    "expense_amount": "$EXPENSE_AMOUNT",
    "expense_date": "$EXPENSE_DATE",
    "expense_policy_id": "$EXPENSE_POLICY_ID",
    "expense_description": "$EXPENSE_DESC_ESC"
}
EOF

# Move to final location safely
rm -f /tmp/mileage_reimbursement_result.json 2>/dev/null || sudo rm -f /tmp/mileage_reimbursement_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/mileage_reimbursement_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/mileage_reimbursement_result.json
chmod 666 /tmp/mileage_reimbursement_result.json 2>/dev/null || sudo chmod 666 /tmp/mileage_reimbursement_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/mileage_reimbursement_result.json"
cat /tmp/mileage_reimbursement_result.json
echo "=== Export Complete ==="