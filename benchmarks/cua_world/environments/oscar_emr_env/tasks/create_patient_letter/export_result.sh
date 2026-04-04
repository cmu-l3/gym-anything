#!/bin/bash
# Export script for Create Patient Letter task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Task Context
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PATIENT_ID=$(cat /tmp/task_patient_id.txt 2>/dev/null || echo "")
INITIAL_COUNT=$(cat /tmp/initial_letter_count.txt 2>/dev/null || echo "0")

if [ -z "$PATIENT_ID" ]; then
    # Fallback lookup if temp file missing
    PATIENT_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Maria' AND last_name='Santos' LIMIT 1")
fi

# 3. Query the Database for Results
# We look for letters for this patient created roughly after task start
# Note: 'editdate' or 'cdate' in Oscar 'letter' table is typically a DATE or DATETIME
echo "Querying letters for patient $PATIENT_ID..."

# Get the most recent letter for this patient
# We fetch relevant columns: id, subject, content (body), status
# JSON escaping is handled carefully
LETTER_DATA=$(oscar_query "SELECT id, subject, letter_text, status, editdate FROM letter WHERE demographic_no='$PATIENT_ID' ORDER BY id DESC LIMIT 1")

LETTER_FOUND="false"
LETTER_ID=""
LETTER_SUBJECT=""
LETTER_BODY=""
LETTER_STATUS=""
LETTER_DATE=""

if [ -n "$LETTER_DATA" ]; then
    LETTER_FOUND="true"
    LETTER_ID=$(echo "$LETTER_DATA" | cut -f1)
    LETTER_SUBJECT=$(echo "$LETTER_DATA" | cut -f2)
    LETTER_BODY=$(echo "$LETTER_DATA" | cut -f3)
    LETTER_STATUS=$(echo "$LETTER_DATA" | cut -f4)
    LETTER_DATE=$(echo "$LETTER_DATA" | cut -f5)
fi

# Get current total count
CURRENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM letter WHERE demographic_no='$PATIENT_ID'" || echo "0")

# 4. Verify Application State (was it running?)
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then APP_RUNNING="true"; fi

# 5. Create JSON Result
# We use Python to handle JSON escaping safely
python3 -c "
import json
import os
import sys

try:
    data = {
        'task_start_timestamp': $TASK_START,
        'patient_id': '$PATIENT_ID',
        'initial_count': int('$INITIAL_COUNT'),
        'current_count': int('$CURRENT_COUNT'),
        'letter_found': $LETTER_FOUND,
        'letter_id': '$LETTER_ID',
        'letter_subject': '''$LETTER_SUBJECT''',
        'letter_body': '''$LETTER_BODY''',
        'letter_status': '$LETTER_STATUS',
        'letter_date': '$LETTER_DATE',
        'app_running': $APP_RUNNING,
        'screenshot_exists': os.path.exists('/tmp/task_final.png')
    }
    print(json.dumps(data))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > /tmp/task_result.json

# 6. Permissions and Cleanup
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="