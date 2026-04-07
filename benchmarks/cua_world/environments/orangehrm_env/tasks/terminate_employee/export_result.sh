#!/bin/bash
echo "=== Exporting terminate_employee results ==="

source /workspace/scripts/task_utils.sh

EMP_NUMBER=$(cat /tmp/target_emp_number.txt 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# Extract Data from Database
# ==============================================================================

if [ -n "$EMP_NUMBER" ]; then
    # 1. Get Termination ID from Employee Table
    TERM_ID=$(orangehrm_db_query "SELECT termination_id FROM hs_hr_employee WHERE emp_number=${EMP_NUMBER};" 2>/dev/null | tr -d '[:space:]')
    
    # 2. If Termination ID exists, get details from Termination Record Table
    if [ -n "$TERM_ID" ] && [ "$TERM_ID" != "NULL" ]; then
        # Use a separator like | that is unlikely to be in the note
        TERM_DETAILS=$(orangehrm_db_query "SELECT 
            t.termination_date, 
            r.name, 
            t.note 
            FROM ohrm_employee_termination_record t 
            LEFT JOIN ohrm_employee_terminate_reason r ON t.reason_id = r.id 
            WHERE t.id=${TERM_ID};" 2>/dev/null)
        
        # Parse result (careful with newlines in notes, but standard query returns tab separated)
        # We'll rely on python in the verifier to parse a JSON structure if we can build it, 
        # but simpler here to dump to text files safely.
        
        ACTUAL_DATE=$(echo "$TERM_DETAILS" | cut -f1)
        ACTUAL_REASON=$(echo "$TERM_DETAILS" | cut -f2)
        ACTUAL_NOTE=$(echo "$TERM_DETAILS" | cut -f3)
        
        IS_TERMINATED="true"
    else
        IS_TERMINATED="false"
        ACTUAL_DATE=""
        ACTUAL_REASON=""
        ACTUAL_NOTE=""
    fi
else
    IS_TERMINATED="false"
    echo "ERROR: Target employee number lost"
fi

# Check initial state to prove change happened
INITIAL_TERM_ID=$(cat /tmp/initial_termination_id.txt 2>/dev/null || echo "NULL")
WAS_ALREADY_TERMINATED="false"
if [ "$INITIAL_TERM_ID" != "NULL" ] && [ -n "$INITIAL_TERM_ID" ]; then
    WAS_ALREADY_TERMINATED="true"
fi

# ==============================================================================
# Create JSON Result
# ==============================================================================

# Use python to safely escape the note string for JSON
python3 -c "
import json
import sys

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'is_terminated': $IS_TERMINATED,
    'was_already_terminated': $WAS_ALREADY_TERMINATED,
    'actual_date': '$ACTUAL_DATE',
    'actual_reason': '$ACTUAL_REASON',
    'actual_note': '''$ACTUAL_NOTE''',
    'screenshot_path': '/tmp/task_final.png'
}
print(json.dumps(data, indent=2))
" > /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="