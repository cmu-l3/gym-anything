#!/bin/bash
echo "=== Exporting process_employee_expenses results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then CLIENT_ID=11; fi

# ---------------------------------------------------------------
# 1. Query Business Partner Data
# ---------------------------------------------------------------
# We look for a BP created AFTER the task start time with the expected name
BP_QUERY="
SELECT 
    c_bpartner_id, 
    name, 
    value, 
    isemployee, 
    isvendor, 
    created 
FROM c_bpartner 
WHERE name = 'Alex Roadwarrior' 
  AND ad_client_id = $CLIENT_ID 
  AND isactive = 'Y'
ORDER BY created DESC LIMIT 1;
"

# Execute query via docker exec (output as separate lines)
BP_DATA=$(idempiere_query "$BP_QUERY")

# Parse BP Data
BP_ID=""
BP_EXISTS="false"
BP_IS_EMPLOYEE="false"
BP_IS_VENDOR="false"
BP_CREATED_TS="0"

if [ -n "$BP_DATA" ]; then
    # Format returned by psql -t -A is usually pipe separated or just raw text depending on setup
    # ideally we use specific formatting. Let's use jq friendly output if possible, 
    # but sticking to simple shell extraction for robustness.
    
    # Re-query specific fields to be safe
    BP_ID=$(idempiere_query "SELECT c_bpartner_id FROM c_bpartner WHERE name='Alex Roadwarrior' AND ad_client_id=$CLIENT_ID ORDER BY created DESC LIMIT 1")
    BP_IS_EMPLOYEE=$(idempiere_query "SELECT isemployee FROM c_bpartner WHERE c_bpartner_id='$BP_ID'")
    BP_IS_VENDOR=$(idempiere_query "SELECT isvendor FROM c_bpartner WHERE c_bpartner_id='$BP_ID'")
    # Get epoch for creation time
    BP_CREATED_RAW=$(idempiere_query "SELECT EXTRACT(EPOCH FROM created) FROM c_bpartner WHERE c_bpartner_id='$BP_ID'")
    BP_CREATED_TS=${BP_CREATED_RAW%.*} # Integer only
    
    if [ -n "$BP_ID" ]; then BP_EXISTS="true"; fi
fi

# ---------------------------------------------------------------
# 2. Query Expense Report Data
# ---------------------------------------------------------------
EXP_REPORT_EXISTS="false"
EXP_REPORT_ID=""
EXP_TOTAL_LINES=0
EXP_TOTAL_AMT=0.0
LINE_1_MATCH="false"
LINE_2_MATCH="false"

if [ "$BP_EXISTS" = "true" ]; then
    # Find expense report linked to this BP
    EXP_REPORT_ID=$(idempiere_query "SELECT s_timeexpense_id FROM s_timeexpense WHERE c_bpartner_id=$BP_ID AND ad_client_id=$CLIENT_ID AND isactive='Y' ORDER BY created DESC LIMIT 1")
    
    if [ -n "$EXP_REPORT_ID" ]; then
        EXP_REPORT_EXISTS="true"
        
        # Count lines
        EXP_TOTAL_LINES=$(idempiere_query "SELECT COUNT(*) FROM s_timeexpenseLine WHERE s_timeexpense_id=$EXP_REPORT_ID AND isactive='Y'")
        
        # Check specific amounts (using range/inclusion)
        # Check for ~150.00
        COUNT_150=$(idempiere_query "SELECT COUNT(*) FROM s_timeexpenseLine WHERE s_timeexpense_id=$EXP_REPORT_ID AND expenseamt BETWEEN 149.99 AND 150.01")
        if [ "$COUNT_150" -ge 1 ]; then LINE_1_MATCH="true"; fi
        
        # Check for ~45.50
        COUNT_45=$(idempiere_query "SELECT COUNT(*) FROM s_timeexpenseLine WHERE s_timeexpense_id=$EXP_REPORT_ID AND expenseamt BETWEEN 45.49 AND 45.51")
        if [ "$COUNT_45" -ge 1 ]; then LINE_2_MATCH="true"; fi
        
        # Sum total
        EXP_TOTAL_AMT=$(idempiere_query "SELECT SUM(expenseamt) FROM s_timeexpenseLine WHERE s_timeexpense_id=$EXP_REPORT_ID AND isactive='Y'")
        if [ -z "$EXP_TOTAL_AMT" ]; then EXP_TOTAL_AMT=0; fi
    fi
fi

# ---------------------------------------------------------------
# 3. Final Screenshot & App Status
# ---------------------------------------------------------------
take_screenshot /tmp/task_final.png
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then APP_RUNNING="true"; fi

# ---------------------------------------------------------------
# 4. Generate JSON Result
# ---------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "bp_exists": $BP_EXISTS,
    "bp_id": "$BP_ID",
    "bp_is_employee": "$BP_IS_EMPLOYEE",
    "bp_is_vendor": "$BP_IS_VENDOR",
    "bp_created_ts": $BP_CREATED_TS,
    "report_exists": $EXP_REPORT_EXISTS,
    "report_lines_count": $EXP_TOTAL_LINES,
    "line_150_match": $LINE_1_MATCH,
    "line_45_match": $LINE_2_MATCH,
    "total_amount": "$EXP_TOTAL_AMT",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved:"
cat /tmp/task_result.json
echo "=== Export complete ==="