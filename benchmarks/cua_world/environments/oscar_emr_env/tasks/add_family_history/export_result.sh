#!/bin/bash
echo "=== Exporting Add Family History results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

PATIENT_ID="80701"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for Family History Data
echo "Querying database..."

# A. Check CPP Table (Primary location for CPP Family History)
CPP_CONTENT=$(oscar_query "SELECT familyHistory FROM casemgmt_cpp WHERE demographic_no='$PATIENT_ID' LIMIT 1" 2>/dev/null || echo "")

# B. Check Case Management Notes (Some versions/configs save as notes)
# Get notes created/updated AFTER task start
NOTES_CONTENT=$(oscar_query "SELECT note FROM casemgmt_note WHERE demographic_no='$PATIENT_ID' AND update_date >= FROM_UNIXTIME($TASK_START)" 2>/dev/null || echo "")

# C. Check for specific issue types if stored structurally
ISSUES_CONTENT=$(oscar_query "
SELECT cn.note FROM casemgmt_note cn
JOIN casemgmt_issue ci ON cn.note_id = ci.note_id
JOIN issue i ON ci.issue_id = i.issue_id
WHERE cn.demographic_no = '$PATIENT_ID' 
AND (i.type = 'FamHistory' OR i.code LIKE '%FamHx%')
" 2>/dev/null || echo "")

# D. Check if any data was modified for this patient during task time
MODIFIED_COUNT=$(oscar_query "
SELECT COUNT(*) FROM casemgmt_cpp 
WHERE demographic_no='$PATIENT_ID' 
AND update_date >= FROM_UNIXTIME($TASK_START)
" 2>/dev/null || echo "0")

NOTES_MODIFIED_COUNT=$(oscar_query "
SELECT COUNT(*) FROM casemgmt_note 
WHERE demographic_no='$PATIENT_ID' 
AND update_date >= FROM_UNIXTIME($TASK_START)
" 2>/dev/null || echo "0")

# 3. Create JSON Export
# Use python to safely escape strings for JSON
python3 -c "
import json
import sys

try:
    data = {
        'task_start': $TASK_START,
        'patient_id': '$PATIENT_ID',
        'cpp_content': '''$CPP_CONTENT''',
        'notes_content': '''$NOTES_CONTENT''',
        'issues_content': '''$ISSUES_CONTENT''',
        'cpp_modified_count': int('$MODIFIED_COUNT'),
        'notes_modified_count': int('$NOTES_MODIFIED_COUNT'),
        'timestamp': '$(date -Iseconds)'
    }
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(data, f, indent=2)
except Exception as e:
    print(f'Error creating JSON: {e}')
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json