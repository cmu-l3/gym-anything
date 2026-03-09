#!/bin/bash
set -e

echo "=== Exporting modify_lead_record result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_PHONE=$(cat /home/ga/Documents/VicidialData/target_lead_phone.txt 2>/dev/null || echo "")

# 3. Query Database for Final State
# We fetch the specific fields we expect to change, plus timestamp and IDs
if [ -n "$TARGET_PHONE" ]; then
    # Create a temp SQL script to output JSON-like structure or specific delimiters
    # Using specific delimiters |~| to parse safely in python
    QUERY="SELECT 
             lead_id, 
             phone_number, 
             address3, 
             alt_phone, 
             comments, 
             rank, 
             owner, 
             first_name, 
             last_name, 
             modify_date 
           FROM vicidial_list 
           WHERE phone_number='$TARGET_PHONE' AND list_id='9001' 
           LIMIT 1;"
           
    RESULT_LINE=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "$QUERY" | tr '\t' '|')
else
    RESULT_LINE=""
fi

# 4. Construct JSON Result
# We will write a python script to verify, but here we just export the raw data to JSON
# safely using jq or python if available, or just simple cat heredoc

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Use python to safely format JSON to avoid quoting issues
python3 -c "
import json
import os
import sys

try:
    line = '$RESULT_LINE'
    parts = line.split('|') if line else []
    
    data = {
        'task_start_ts': $TASK_START,
        'target_phone': '$TARGET_PHONE',
        'found': False
    }
    
    if len(parts) >= 10:
        data['found'] = True
        data['lead_id'] = parts[0]
        data['phone_number'] = parts[1]
        data['address3'] = parts[2]
        data['alt_phone'] = parts[3]
        data['comments'] = parts[4]
        data['rank'] = parts[5]
        data['owner'] = parts[6]
        data['first_name'] = parts[7]
        data['last_name'] = parts[8]
        data['modify_date'] = parts[9]
    
    print(json.dumps(data, indent=2))
except Exception as e:
    print(json.dumps({'error': str(e), 'found': False}))

" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported data:"
cat /tmp/task_result.json
echo "=== Export complete ==="