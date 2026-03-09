#!/bin/bash
echo "=== Exporting create_third_party_risk results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# 3. Query the database for the specific record created by the agent
# We look for the specific title requested in the task description
# We fetch fields to verify content accuracy
QUERY="SELECT id, title, description, threats, vulnerabilities, risk_mitigation_strategy_id, review, created 
       FROM third_party_risks 
       WHERE title = 'Cloud Provider Data Breach - TechCloud Solutions' 
       AND deleted = 0 
       ORDER BY created DESC LIMIT 1;"

# Use a temporary file to store raw SQL output to handle special characters safely
RAW_RESULT_FILE=$(mktemp)

docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -B -e "$QUERY" > "$RAW_RESULT_FILE" 2>/dev/null || true

# Check if we got a result
if [ -s "$RAW_RESULT_FILE" ]; then
    RECORD_FOUND="true"
    # Read fields. MySQL -B outputs tab-separated values.
    # We use python to parse this safely into the JSON to avoid shell escaping hell
    read -r DB_ID DB_TITLE DB_DESC DB_THREATS DB_VULNS DB_MITIGATION DB_REVIEW DB_CREATED < "$RAW_RESULT_FILE"
else
    RECORD_FOUND="false"
    DB_ID=""
    DB_TITLE=""
    DB_DESC=""
    DB_THREATS=""
    DB_VULNS=""
    DB_MITIGATION=""
    DB_REVIEW=""
    DB_CREATED=""
fi

# 4. Get final count to check against initial count (anti-gaming: did they actually add something?)
FINAL_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT COUNT(*) FROM third_party_risks WHERE deleted=0;" 2>/dev/null || echo "0")

# 5. Construct JSON result using Python for robustness against special characters in description
python3 -c "
import json
import os
import sys

try:
    record_found = '$RECORD_FOUND' == 'true'
    
    # Safely read the raw file content if it exists
    raw_data = {}
    if record_found:
        with open('$RAW_RESULT_FILE', 'r') as f:
            content = f.read().strip()
            parts = content.split('\t')
            if len(parts) >= 8:
                raw_data = {
                    'id': parts[0],
                    'title': parts[1],
                    'description': parts[2],
                    'threats': parts[3],
                    'vulnerabilities': parts[4],
                    'mitigation_id': parts[5],
                    'review_date': parts[6],
                    'created': parts[7]
                }

    result = {
        'record_found': record_found,
        'record_data': raw_data,
        'task_start_ts': $TASK_START,
        'task_end_ts': $TASK_END,
        'initial_count': int('$INITIAL_COUNT'),
        'final_count': int('$FINAL_COUNT'),
        'screenshot_path': '/tmp/task_final.png'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    print(f'Error generating JSON: {e}', file=sys.stderr)
    # Fallback JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)
"

# Clean up
rm -f "$RAW_RESULT_FILE"

# Set permissions so verifier can read it
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json