#!/bin/bash
# Export script for Update Clinic Details task
# Exports the final state of the facility table

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_facility_count.txt 2>/dev/null || echo "0")

# 3. Query Current State
# We fetch the facility that looks most like the target (ID 1) OR any facility that matches the new phone number
# This helps us detect if they created a new one instead of updating.

# Fetch ID 1 explicitly
ID1_DATA=$(oscar_query "SELECT id, name, address, city, province, postal, phone, fax FROM facility WHERE id=1")

# Fetch any facility matching the new phone number (to catch duplicates)
MATCHING_DATA=$(oscar_query "SELECT id, name, address, city, province, postal, phone, fax FROM facility WHERE phone LIKE '%416-555-0198%' LIMIT 1")

# Get final count
FINAL_COUNT=$(oscar_query "SELECT count(*) FROM facility")

# 4. Prepare JSON Data
# We need to construct a valid JSON manually or via python

python3 -c "
import json
import sys

def parse_sql_row(row_str):
    if not row_str: return None
    parts = row_str.split('\t')
    if len(parts) < 8: return None
    return {
        'id': parts[0],
        'name': parts[1],
        'address': parts[2],
        'city': parts[3],
        'province': parts[4],
        'postal': parts[5],
        'phone': parts[6],
        'fax': parts[7]
    }

id1_raw = \"\"\"$ID1_DATA\"\"\"
match_raw = \"\"\"$MATCHING_DATA\"\"\"

result = {
    'task_start': $TASK_START,
    'initial_count': int('$INITIAL_COUNT'),
    'final_count': int('$FINAL_COUNT'),
    'facility_id_1': parse_sql_row(id1_raw),
    'facility_matching_target': parse_sql_row(match_raw),
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 5. Permission fix
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json