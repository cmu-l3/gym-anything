#!/bin/bash
echo "=== Exporting create_bank_statement result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve task start time
TASK_START_TS=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Identify the Bank Statement
# We search for the specific name created by the agent
CLIENT_ID=$(get_gardenworld_client_id)
TARGET_NAME="Dec 2024 Mid-Month Statement"

echo "Searching for Bank Statement: '$TARGET_NAME'..."

# Get ID
BS_ID=$(idempiere_query "SELECT c_bankstatement_id FROM c_bankstatement WHERE name='$TARGET_NAME' AND ad_client_id=${CLIENT_ID:-11} ORDER BY created DESC LIMIT 1")

FOUND="false"
HEADER_JSON="{}"
LINES_JSON="[]"

if [ -n "$BS_ID" ] && [ "$BS_ID" != "" ]; then
    FOUND="true"
    echo "Found Bank Statement ID: $BS_ID"

    # 2. Extract Header Details
    # Columns: Name, StatementDate, DocStatus, Created (timestamp)
    # Note: 'created' in iDempiere PG is a timestamp.
    HEADER_DATA=$(idempiere_query "SELECT name, statementdate, docstatus, created FROM c_bankstatement WHERE c_bankstatement_id=$BS_ID")
    
    # Parse pipe-separated output (psql default for one row might vary, but idempiere_query uses -A -t which is usually pipe or aligned)
    # Ideally use a separator we can control or query individual fields to be safe.
    # Let's query individually to avoid delimiter collision in text fields.
    NAME=$(idempiere_query "SELECT name FROM c_bankstatement WHERE c_bankstatement_id=$BS_ID")
    DATE=$(idempiere_query "SELECT statementdate FROM c_bankstatement WHERE c_bankstatement_id=$BS_ID")
    STATUS=$(idempiere_query "SELECT docstatus FROM c_bankstatement WHERE c_bankstatement_id=$BS_ID")
    CREATED=$(idempiere_query "SELECT created FROM c_bankstatement WHERE c_bankstatement_id=$BS_ID")
    
    # Construct Header JSON safely
    HEADER_JSON=$(python3 -c "import json; print(json.dumps({
        'name': '''$NAME''',
        'date': '$DATE',
        'status': '$STATUS',
        'created': '$CREATED'
    }))")

    # 3. Extract Line Details
    # Get all lines ordered by line number or date
    # We fetch relevant columns and format as a JSON list using Python to handle special chars safely
    
    # Get raw data: LineID|LineDate|Amt|Description
    # We use a custom query with a separator that is unlikely to be in the description, e.g., '|||'
    RAW_LINES=$(docker exec idempiere-postgres psql -U adempiere -d idempiere -t -A -F "|||" -c "SELECT line, dateacct, stmtamt, description FROM c_bankstatementline WHERE c_bankstatement_id=$BS_ID ORDER BY line, dateacct")
    
    if [ -n "$RAW_LINES" ]; then
        LINES_JSON=$(python3 -c "
import json
import sys

lines = []
raw_data = '''$RAW_LINES'''
if raw_data.strip():
    for row in raw_data.split('\n'):
        if '|||' in row:
            parts = row.split('|||')
            if len(parts) >= 4:
                lines.append({
                    'line_no': parts[0],
                    'date': parts[1],
                    'amount': float(parts[2]) if parts[2] else 0.0,
                    'description': parts[3]
                })
print(json.dumps(lines))
")
    fi
else
    echo "Bank Statement not found with name: '$TARGET_NAME'"
fi

# 4. Compile Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import time

result = {
    'task_start_ts': $TASK_START_TS,
    'export_ts': int(time.time()),
    'found': $FOUND,
    'header': $HEADER_JSON,
    'lines': $LINES_JSON,
    'screenshot_path': '/tmp/task_final.png'
}
print(json.dumps(result, indent=2))
" > "$TEMP_JSON"

# Move to standard location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="