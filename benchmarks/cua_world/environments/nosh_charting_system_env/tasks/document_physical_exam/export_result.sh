#!/bin/bash
set -e
echo "=== Exporting document_physical_exam results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract Data from Database
# We need to read the specific fields from the 'pe' table for our encounter ID (200)
# We select the most recent record for this encounter
EID=200

# Helper to run SQL and escape JSON
# We fetch specific columns that map to the body systems requested
# NOSH columns: pe_gen1 (General), pe_eye1 (HEENT/Eye), pe_ent1 (HEENT/ENT), pe_neck1 (Neck), pe_cv1 (CV), pe_lung1 (Lungs), pe_abd1 (Abd)
# We concatenate eye and ent for HEENT check

echo "Querying database..."
SQL_QUERY="SELECT 
    peID,
    eid,
    pe_gen1 as general,
    CONCAT(IFNULL(pe_eye1,''), ' ', IFNULL(pe_ent1,'')) as heent,
    pe_neck1 as neck,
    pe_cv1 as cv,
    pe_lung1 as lungs,
    pe_abd1 as abdomen,
    date
FROM pe 
WHERE eid=${EID} 
ORDER BY peID DESC LIMIT 1"

# Execute query and format as JSON using jq (safest for multiline text)
# Docker exec doesn't have jq usually, so we dump raw TSV and process in host
RAW_DATA=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "$SQL_QUERY" 2>/dev/null || true)

# Process Data
PE_RECORD_EXISTS="false"
PE_ID=0
GEN_TEXT=""
HEENT_TEXT=""
NECK_TEXT=""
CV_TEXT=""
LUNGS_TEXT=""
ABD_TEXT=""

if [ -n "$RAW_DATA" ]; then
    PE_RECORD_EXISTS="true"
    # Parse tab separated values
    # Note: Text fields might contain tabs or newlines, simpler to fetch one by one if strict, 
    # but for verification, we'll try simple cut first. 
    # Better approach for robustness: Fetch each field individually to avoiding parsing issues.
    
    PE_ID=$(echo "$RAW_DATA" | awk -F'\t' '{print $1}')
    GEN_TEXT=$(echo "$RAW_DATA" | awk -F'\t' '{print $3}')
    HEENT_TEXT=$(echo "$RAW_DATA" | awk -F'\t' '{print $4}')
    NECK_TEXT=$(echo "$RAW_DATA" | awk -F'\t' '{print $5}')
    CV_TEXT=$(echo "$RAW_DATA" | awk -F'\t' '{print $6}')
    LUNGS_TEXT=$(echo "$RAW_DATA" | awk -F'\t' '{print $7}')
    ABD_TEXT=$(echo "$RAW_DATA" | awk -F'\t' '{print $8}')
fi

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_PE_COUNT=$(cat /tmp/initial_pe_count.txt 2>/dev/null || echo "0")

# 3. Create Result JSON
# Python is safer for JSON construction with potentially messy text
python3 -c "
import json
import sys

data = {
    'pe_record_exists': $PE_RECORD_EXISTS,
    'pe_id': '$PE_ID',
    'initial_count': $INITIAL_PE_COUNT,
    'findings': {
        'general': '''$GEN_TEXT''',
        'heent': '''$HEENT_TEXT''',
        'neck': '''$NECK_TEXT''',
        'cv': '''$CV_TEXT''',
        'lungs': '''$LUNGS_TEXT''',
        'abdomen': '''$ABD_TEXT'''
    },
    'timestamps': {
        'start': $TASK_START,
        'end': $TASK_END
    },
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="