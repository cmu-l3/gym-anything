#!/bin/bash
echo "=== Exporting create_commission_plan results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)
CLIENT_ID=${CLIENT_ID:-11} # Default to 11 if query fails

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query the Commission Header
echo "--- Querying Commission Header ---"
# We fetch specific fields to verify configuration
# Using a specific delimiter '|' for parsing in Python
HEADER_DATA=$(idempiere_query "
SELECT 
    c.c_commission_id, 
    c.name, 
    c.value, 
    c.docbasistype, 
    c.frequencytype, 
    c.listdetails,
    bp.name as bp_name, 
    cur.iso_code as currency,
    c.created
FROM c_commission c
LEFT JOIN c_bpartner bp ON c.c_bpartner_id = bp.c_bpartner_id
LEFT JOIN c_currency cur ON c.c_currency_id = cur.c_currency_id
WHERE c.value='COMM-Q3-2024' AND c.ad_client_id=$CLIENT_ID
")

# 3. Query Commission Lines if header exists
LINES_JSON="[]"
if [ -n "$HEADER_DATA" ]; then
    COMMISSION_ID=$(echo "$HEADER_DATA" | cut -d'|' -f1)
    
    # We construct a JSON array of lines manually or via python helper
    # Here we'll just dump the raw line data and parse it in python
    echo "--- Querying Commission Lines for ID $COMMISSION_ID ---"
    
    LINES_DATA=$(idempiere_query "
    SELECT 
        cl.line,
        cl.amtmultiplier,
        cl.ispositiveonly,
        pc.name as category_name
    FROM c_commissionline cl
    LEFT JOIN m_product_category pc ON cl.m_product_category_id = pc.m_product_category_id
    WHERE cl.c_commission_id=$COMMISSION_ID
    ORDER BY cl.amtmultiplier
    ")
fi

# 4. Get counts
INITIAL_COUNT=$(cat /tmp/initial_commission_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_commission WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")

# 5. Construct JSON Result
# We use a python script to safely format the SQL output into JSON to avoid escaping hell in bash
python3 -c "
import json
import sys
import time

def safe_split(data):
    if not data: return []
    return [row.split('|') for row in data.strip().split('\n') if row]

header_raw = \"\"\"$HEADER_DATA\"\"\"
lines_raw = \"\"\"$LINES_DATA\"\"\"
task_start = $TASK_START
initial_count = int(\"$INITIAL_COUNT\")
final_count = int(\"$FINAL_COUNT\")

result = {
    'task_start': task_start,
    'record_created': False,
    'header': None,
    'lines': [],
    'initial_count': initial_count,
    'final_count': final_count,
    'timestamp': time.time()
}

if header_raw.strip():
    parts = header_raw.strip().split('|')
    if len(parts) >= 9:
        # Check creation time against task start (Postgres timestamp format handling might be needed, 
        # but purely existence checking is often enough combined with unique search key)
        result['record_created'] = True
        result['header'] = {
            'id': parts[0],
            'name': parts[1],
            'value': parts[2],
            'docbasistype': parts[3],
            'frequencytype': parts[4],
            'listdetails': parts[5],
            'bp_name': parts[6],
            'currency': parts[7],
            'created_raw': parts[8]
        }

if lines_raw.strip():
    for row in lines_raw.strip().split('\n'):
        if not row: continue
        parts = row.split('|')
        if len(parts) >= 3:
            line = {
                'line_no': parts[0],
                'multiplier': float(parts[1]) if parts[1] and parts[1] != '0' else 0.0,
                'positive_only': parts[2],
                'category': parts[3] if len(parts) > 3 and parts[3] else None
            }
            result['lines'].append(line)

print(json.dumps(result, indent=2))
" > /tmp/task_result.json

# Move to final location (handling permissions)
cp /tmp/task_result.json /tmp/final_result.json
chmod 666 /tmp/final_result.json 2>/dev/null || true

echo "Result saved to /tmp/final_result.json"
cat /tmp/final_result.json
echo "=== Export complete ==="