#!/bin/bash
echo "=== Exporting issue_written_warning result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Baseline Data
INITIAL_COUNT=$(cat /tmp/initial_warning_count.txt 2>/dev/null || echo "0")
BASELINE_MAX_ID=$(cat /tmp/baseline_max_warning_id.txt 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Query Current State
CURRENT_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM ncic_warnings")

# 4. Find the specific record created during the task
# We look for a warning created after the baseline max ID
# We select the most recent one
WARNING_DATA=$(opencad_db_query "
    SELECT w.id, w.name_id, w.warning_name, w.remarks, n.name
    FROM ncic_warnings w
    LEFT JOIN ncic_names n ON w.name_id = n.id
    WHERE w.id > $BASELINE_MAX_ID
    ORDER BY w.id DESC LIMIT 1
")

# Parse the result (Tab separated by default with -N switch in helper)
# Note: Helper uses -N (skip headers)
WARNING_FOUND="false"
REC_ID=""
REC_CIV_ID=""
REC_REASON=""
REC_REMARKS=""
REC_CIV_NAME=""

if [ -n "$WARNING_DATA" ]; then
    WARNING_FOUND="true"
    REC_ID=$(echo "$WARNING_DATA" | cut -f1)
    REC_CIV_ID=$(echo "$WARNING_DATA" | cut -f2)
    REC_REASON=$(echo "$WARNING_DATA" | cut -f3)
    REC_REMARKS=$(echo "$WARNING_DATA" | cut -f4)
    REC_CIV_NAME=$(echo "$WARNING_DATA" | cut -f5)
fi

# 5. Check Anti-Gaming (Did they issue a citation instead?)
CITATION_COUNT_INCREASED="false"
# Simple check if any citation was added
NEW_CITATIONS=$(opencad_db_query "SELECT COUNT(*) FROM ncic_citations WHERE issued_date >= CURDATE()" 2>/dev/null)
# Depending on schema, created_at might not exist or be named differently.
# Safer check: Count citations > known max? We didn't save max citation id.
# We'll rely on the warning check primarily. If warning found = false, we fail.

# 6. Construct JSON Result
# Use python for safer JSON construction to handle special chars/newlines in narrative
python3 -c "
import json
import sys

data = {
    'initial_count': int('$INITIAL_COUNT'),
    'current_count': int('$CURRENT_COUNT'),
    'warning_found': '$WARNING_FOUND' == 'true',
    'record': {
        'id': '$REC_ID',
        'civilian_id': '$REC_CIV_ID',
        'reason': '''$REC_REASON''',
        'remarks': '''$REC_REMARKS''',
        'civilian_name': '''$REC_CIV_NAME'''
    },
    'timestamp': '$TASK_START_TIME'
}

with open('/tmp/issue_written_warning_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/issue_written_warning_result.json 2>/dev/null || true

echo "Result exported to /tmp/issue_written_warning_result.json"
cat /tmp/issue_written_warning_result.json
echo "=== Export complete ==="