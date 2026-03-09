#!/bin/bash
# Export script for Add Medical History task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PATIENT_ID=$(cat /tmp/task_patient_id.txt 2>/dev/null || echo "")
INITIAL_COUNT=$(cat /tmp/initial_pmh_count.txt 2>/dev/null || echo "0")
INITIAL_KEYWORD_COUNT=$(cat /tmp/initial_keyword_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# If no patient ID, try to find it again
if [ -z "$PATIENT_ID" ]; then
    PATIENT_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Maria' AND last_name='Santos' LIMIT 1" 2>/dev/null)
fi

echo "Checking database for patient ID: $PATIENT_ID"

# Query 1: Get all Medical History entries added AFTER task start
# This joins notes -> issue_notes -> issues (type=MedHistory)
NEW_PMH_ENTRIES=$(oscar_query "
    SELECT cn.note 
    FROM casemgmt_note cn
    JOIN casemgmt_issue_notes cin ON cn.note_id = cin.note_id
    JOIN casemgmt_issue ci ON cin.id = ci.issue_id
    WHERE cn.demographic_no = '$PATIENT_ID'
    AND ci.type = 'MedHistory'
    AND cn.note NOT LIKE '%[Archived]%'
    AND (UNIX_TIMESTAMP(cn.update_date) >= $TASK_START OR UNIX_TIMESTAMP(cn.observation_date) >= $TASK_START)
" 2>/dev/null)

# Query 2: Fallback - Get ANY notes with keywords added AFTER task start
# (In case they were added but not correctly linked to MedHistory type, partial credit)
NEW_KEYWORD_NOTES=$(oscar_query "
    SELECT note 
    FROM casemgmt_note 
    WHERE demographic_no = '$PATIENT_ID'
    AND (LOWER(note) LIKE '%cholecystectomy%' OR LOWER(note) LIKE '%pneumonia%')
    AND (UNIX_TIMESTAMP(update_date) >= $TASK_START OR UNIX_TIMESTAMP(observation_date) >= $TASK_START)
" 2>/dev/null)

# Query 3: Check Casemgmt_CPP table (alternative storage in some Oscar configs)
CPP_NOTES=$(oscar_query "
    SELECT medical_history_note 
    FROM casemgmt_cpp 
    WHERE demographic_no = '$PATIENT_ID'
" 2>/dev/null)

# Check if app was running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Prepare JSON Output
# We use Python to robustly construct the JSON to handle newlines/quotes in SQL output
python3 -c "
import json
import sys

def clean_sql_output(output):
    if not output: return []
    return [line.strip() for line in output.split('\n') if line.strip()]

pmh_entries = clean_sql_output('''$NEW_PMH_ENTRIES''')
keyword_notes = clean_sql_output('''$NEW_KEYWORD_NOTES''')
cpp_notes = clean_sql_output('''$CPP_NOTES''')

result = {
    'task_start': $TASK_START,
    'patient_id': '$PATIENT_ID',
    'initial_pmh_count': int('$INITIAL_COUNT'),
    'initial_keyword_count': int('$INITIAL_KEYWORD_COUNT'),
    'new_pmh_entries': pmh_entries,
    'new_keyword_notes': keyword_notes,
    'cpp_notes': cpp_notes,
    'app_was_running': $APP_RUNNING == True,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="