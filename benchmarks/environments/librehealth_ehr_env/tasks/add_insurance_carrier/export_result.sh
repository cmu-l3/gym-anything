#!/bin/bash
echo "=== Exporting Add Insurance Carrier Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Query the Database for the Result
# We look for the specific company created during the task
# Use JSON_OBJECT (if MariaDB version supports it) or manual construction to robustly export data

# Check if the record exists and get its details
# We select the most recently added record matching the name to handle duplicates if agent clicked twice
SQL_QUERY="SELECT id, name, street, city, state, postal_code, phone, cms_id FROM insurance_companies WHERE name LIKE 'Cigna Health Spring%' ORDER BY id DESC LIMIT 1"

# Execute query using docker exec (raw output tab separated)
RAW_RESULT=$(docker exec librehealth-db mysql -u libreehr -ps3cret libreehr -N -e "$SQL_QUERY" 2>/dev/null)

# Parse the raw result into variables
# Expected format: ID \t Name \t Street \t City \t State \t Zip \t Phone \t CMS_ID
REC_ID=$(echo "$RAW_RESULT" | awk -F'\t' '{print $1}')
REC_NAME=$(echo "$RAW_RESULT" | awk -F'\t' '{print $2}')
REC_STREET=$(echo "$RAW_RESULT" | awk -F'\t' '{print $3}')
REC_CITY=$(echo "$RAW_RESULT" | awk -F'\t' '{print $4}')
REC_STATE=$(echo "$RAW_RESULT" | awk -F'\t' '{print $5}')
REC_ZIP=$(echo "$RAW_RESULT" | awk -F'\t' '{print $6}')
REC_PHONE=$(echo "$RAW_RESULT" | awk -F'\t' '{print $7}')
REC_CMS_ID=$(echo "$RAW_RESULT" | awk -F'\t' '{print $8}')

# 3. Check Counts (Anti-Gaming)
FINAL_COUNT=$(librehealth_query "SELECT COUNT(*) FROM insurance_companies")
INITIAL_COUNT=$(cat /tmp/lh_initial_insurance_count 2>/dev/null || echo "0")
COUNT_DIFF=$((FINAL_COUNT - INITIAL_COUNT))

# 4. Verify Record Existence
RECORD_FOUND="false"
if [ -n "$REC_ID" ]; then
    RECORD_FOUND="true"
fi

# 5. Construct JSON Result using Python for safety
# (Handling potential quotes/special chars in SQL output)
python3 -c "
import json
import os

result = {
    'record_found': $RECORD_FOUND,
    'record': {
        'id': '$REC_ID',
        'name': '''$REC_NAME''',
        'street': '''$REC_STREET''',
        'city': '''$REC_CITY''',
        'state': '''$REC_STATE''',
        'zip': '''$REC_ZIP''',
        'phone': '''$REC_PHONE''',
        'cms_id': '''$REC_CMS_ID'''
    },
    'stats': {
        'initial_count': int('$INITIAL_COUNT'),
        'final_count': int('$FINAL_COUNT'),
        'count_diff': int('$COUNT_DIFF')
    },
    'timestamp': '$(date +%s)'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 6. Set permissions for the result file
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="