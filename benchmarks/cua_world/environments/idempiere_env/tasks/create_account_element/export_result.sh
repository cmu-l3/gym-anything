#!/bin/bash
echo "=== Exporting create_account_element result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query the database for the account
echo "--- Querying database for account 76500 ---"

# We fetch relevant fields. Note: We use COALESCE to handle nulls safely for the JSON construction
# accounttype: E=Expense, A=Asset, etc.
# accountsign: N=Natural, D=Debit, C=Credit
QUERY="SELECT value, name, description, accounttype, accountsign, issummary, isactive, EXTRACT(EPOCH FROM created)::bigint as created_ts 
       FROM c_elementvalue 
       WHERE value='76500' AND ad_client_id=$CLIENT_ID"

# Execute query and parse into variables (using | separator for safety against spaces in names)
RESULT_LINE=$(idempiere_query "$QUERY" | head -n 1)

FOUND="false"
VAL=""
NAME=""
DESC=""
TYPE=""
SIGN=""
SUMMARY=""
ACTIVE=""
CREATED_TS="0"

if [ -n "$RESULT_LINE" ]; then
    FOUND="true"
    # Parse the pipe-delimited result (default psql output is pipe aligned, but we requested -A -t in utils which is pipe separated?)
    # ideally we set the separator explicitly.
    # Let's re-run with explicit separator for safety
    RESULT_LINE=$(docker exec idempiere-postgres psql -U adempiere -d idempiere -t -A -F "|" -c "$QUERY" 2>/dev/null)
    
    VAL=$(echo "$RESULT_LINE" | cut -d'|' -f1)
    NAME=$(echo "$RESULT_LINE" | cut -d'|' -f2)
    DESC=$(echo "$RESULT_LINE" | cut -d'|' -f3)
    TYPE=$(echo "$RESULT_LINE" | cut -d'|' -f4)
    SIGN=$(echo "$RESULT_LINE" | cut -d'|' -f5)
    SUMMARY=$(echo "$RESULT_LINE" | cut -d'|' -f6)
    ACTIVE=$(echo "$RESULT_LINE" | cut -d'|' -f7)
    CREATED_TS=$(echo "$RESULT_LINE" | cut -d'|' -f8)
fi

# 3. Check timestamps (Anti-gaming)
CREATED_DURING_TASK="false"
if [ "$FOUND" = "true" ] && [ "$CREATED_TS" -ge "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

# 4. JSON Construction
# Use Python to construct JSON to handle escaping of strings safely
python3 -c "
import json
import sys

data = {
    'found': $FOUND,
    'value': '$VAL',
    'name': '''$NAME''',
    'description': '''$DESC''',
    'account_type': '$TYPE',
    'account_sign': '$SIGN',
    'is_summary': '$SUMMARY',
    'is_active': '$ACTIVE',
    'created_timestamp': $CREATED_TS,
    'task_start_timestamp': $TASK_START,
    'created_during_task': $CREATED_DURING_TASK
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="