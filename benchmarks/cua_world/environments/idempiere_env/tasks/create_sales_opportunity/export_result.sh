#!/bin/bash
set -e
echo "=== Exporting create_sales_opportunity results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_opp_count.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)

# 3. Query the specific opportunity by Name
# We select key fields to verify the task requirements
# Use JSON construction within bash to handle potential nulls/formatting safely
echo "--- Querying Database for 'Oak Street Office Park' ---"

# We fetch the raw pipe-delimited string first
RAW_DATA=$(idempiere_query "
SELECT 
    o.C_Opportunity_ID,
    o.ExpectedAmt,
    o.Probability,
    o.ExpectedCloseDate,
    o.Description,
    bp.Name as BPName,
    ss.Name as StageName,
    EXTRACT(EPOCH FROM o.Created) as CreatedTs
FROM C_Opportunity o
LEFT JOIN C_BPartner bp ON o.C_BPartner_ID = bp.C_BPartner_ID
LEFT JOIN C_SalesStage ss ON o.C_SalesStage_ID = ss.C_SalesStage_ID
WHERE o.Name = 'Oak Street Office Park' 
  AND o.AD_Client_ID = ${CLIENT_ID:-11}
  AND o.IsActive = 'Y'
ORDER BY o.Created DESC 
LIMIT 1
")

# Parse the raw data (format: ID|Amt|Prob|Date|Desc|BPName|StageName|CreatedTs)
if [ -n "$RAW_DATA" ]; then
    FOUND="true"
    OPP_ID=$(echo "$RAW_DATA" | cut -d'|' -f1)
    AMT=$(echo "$RAW_DATA" | cut -d'|' -f2)
    PROB=$(echo "$RAW_DATA" | cut -d'|' -f3)
    CLOSE_DATE=$(echo "$RAW_DATA" | cut -d'|' -f4)
    DESC=$(echo "$RAW_DATA" | cut -d'|' -f5)
    BP_NAME=$(echo "$RAW_DATA" | cut -d'|' -f6)
    STAGE_NAME=$(echo "$RAW_DATA" | cut -d'|' -f7)
    CREATED_TS=$(echo "$RAW_DATA" | cut -d'|' -f8) # Unix timestamp
else
    FOUND="false"
    OPP_ID=""
    AMT="0"
    PROB="0"
    CLOSE_DATE=""
    DESC=""
    BP_NAME=""
    STAGE_NAME=""
    CREATED_TS="0"
fi

# 4. Get current total count for secondary verification
FINAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM C_Opportunity WHERE AD_Client_ID=${CLIENT_ID:-11} AND IsActive='Y'" 2>/dev/null || echo "0")

# 5. Export to JSON
# Using python to safely construct JSON and avoid escaping issues with Description
python3 -c "
import json
import sys

data = {
    'task_start_ts': $TASK_START,
    'found': $FOUND,
    'record': {
        'id': '$OPP_ID',
        'amount': '$AMT',
        'probability': '$PROB',
        'close_date': '$CLOSE_DATE',
        'description': '''$DESC''',
        'bp_name': '''$BP_NAME''',
        'stage_name': '''$STAGE_NAME''',
        'created_ts': float('$CREATED_TS') if '$CREATED_TS' else 0
    },
    'counts': {
        'initial': int('$INITIAL_COUNT'),
        'final': int('$FINAL_COUNT')
    },
    'screenshot_path': '/tmp/task_final.png'
}
print(json.dumps(data, indent=2))
" > /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="