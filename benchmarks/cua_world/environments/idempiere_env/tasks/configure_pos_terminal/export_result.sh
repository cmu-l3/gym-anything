#!/bin/bash
set -e
echo "=== Exporting configure_pos_terminal results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task start time and initial count
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_pos_count.txt 2>/dev/null || echo "0")

# 3. Query the database for the specific record
# We join with related tables to get readable names for verification
CLIENT_ID=$(get_gardenworld_client_id)
CLIENT_ID=${CLIENT_ID:-11}

echo "Querying database for 'Express Lane 1'..."

# Construct SQL query to get details
# Using separator | for easier parsing
QUERY="
SELECT 
    p.C_POS_ID,
    p.Name,
    o.Name as Org,
    w.Name as Warehouse,
    pl.Name as PriceList,
    cb.Name as CashBook,
    u.Name as SalesRep,
    p.IsModifyPrice,
    p.IsActive,
    EXTRACT(EPOCH FROM p.Created) as CreatedTime
FROM C_POS p
LEFT JOIN AD_Org o ON p.AD_Org_ID = o.AD_Org_ID
LEFT JOIN M_Warehouse w ON p.M_Warehouse_ID = w.M_Warehouse_ID
LEFT JOIN M_PriceList pl ON p.M_PriceList_ID = pl.M_PriceList_ID
LEFT JOIN C_CashBook cb ON p.C_CashBook_ID = cb.C_CashBook_ID
LEFT JOIN AD_User u ON p.SalesRep_ID = u.AD_User_ID
WHERE p.Name = 'Express Lane 1' 
  AND p.AD_Client_ID = $CLIENT_ID
"

# Execute query via Docker
RESULT_LINE=$(idempiere_query "$QUERY" | head -n 1)

# Initialize result variables
RECORD_FOUND="false"
POS_ID=""
POS_NAME=""
POS_ORG=""
POS_WAREHOUSE=""
POS_PRICELIST=""
POS_CASHBOOK=""
POS_SALESREP=""
POS_MODIFYPRICE=""
POS_ACTIVE=""
POS_CREATED=""

if [ -n "$RESULT_LINE" ]; then
    RECORD_FOUND="true"
    # Parse the pipe-separated values (default psql output for -A is pipe)
    # Actually idempiere_query uses -A (unaligned) which usually uses | as separator
    
    # Let's handle the extraction carefully using cut
    POS_ID=$(echo "$RESULT_LINE" | cut -d'|' -f1)
    POS_NAME=$(echo "$RESULT_LINE" | cut -d'|' -f2)
    POS_ORG=$(echo "$RESULT_LINE" | cut -d'|' -f3)
    POS_WAREHOUSE=$(echo "$RESULT_LINE" | cut -d'|' -f4)
    POS_PRICELIST=$(echo "$RESULT_LINE" | cut -d'|' -f5)
    POS_CASHBOOK=$(echo "$RESULT_LINE" | cut -d'|' -f6)
    POS_SALESREP=$(echo "$RESULT_LINE" | cut -d'|' -f7)
    POS_MODIFYPRICE=$(echo "$RESULT_LINE" | cut -d'|' -f8)
    POS_ACTIVE=$(echo "$RESULT_LINE" | cut -d'|' -f9)
    POS_CREATED=$(echo "$RESULT_LINE" | cut -d'|' -f10)
fi

# Get final count
FINAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM C_POS WHERE AD_Client_ID=$CLIENT_ID" 2>/dev/null || echo "0")

# Check if application (Firefox) is running
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON Result
# We use Python to generate valid JSON to avoid shell escaping issues
python3 -c "
import json
import os

result = {
    'record_found': $RECORD_FOUND,
    'pos_id': '$POS_ID',
    'name': '$POS_NAME',
    'org': '$POS_ORG',
    'warehouse': '$POS_WAREHOUSE',
    'pricelist': '$POS_PRICELIST',
    'cashbook': '$POS_CASHBOOK',
    'salesrep': '$POS_SALESREP',
    'is_modify_price': '$POS_MODIFYPRICE',
    'is_active': '$POS_ACTIVE',
    'created_timestamp': float('${POS_CREATED:-0}'),
    'task_start_timestamp': float('${TASK_START:-0}'),
    'initial_count': int('${INITIAL_COUNT:-0}'),
    'final_count': int('${FINAL_COUNT:-0}'),
    'app_running': $APP_RUNNING
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="