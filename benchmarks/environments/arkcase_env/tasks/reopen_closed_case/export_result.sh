#!/bin/bash
echo "=== Exporting reopen_closed_case result ==="

source /workspace/scripts/task_utils.sh

# Ensure port-forward is active for API queries
ensure_portforward

# 1. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
CASE_ID=$(cat /tmp/reopen_case_id.txt 2>/dev/null || echo "")
INITIAL_NOTE_COUNT=$(cat /tmp/initial_note_count.txt 2>/dev/null || echo "0")

echo "Checking Case ID: $CASE_ID"

# 2. Query Final API State
if [ -n "$CASE_ID" ]; then
    # Get Case Details
    CASE_JSON=$(curl -sk -X GET \
        -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
        -H "Accept: application/json" \
        "${ARKCASE_URL}/api/v1/plugin/complaint/${CASE_ID}" 2>/dev/null)
    
    # Get Notes
    # Try complaint-specific notes first, then generic
    NOTES_JSON=$(curl -sk -X GET \
        -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
        -H "Accept: application/json" \
        "${ARKCASE_URL}/api/v1/plugin/complaint/${CASE_ID}/notes" 2>/dev/null)
    
    # Validation of notes response
    if ! echo "$NOTES_JSON" | grep -q "\["; then
        # Fallback to service note endpoint
        NOTES_JSON=$(curl -sk -X GET \
            -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
            -H "Accept: application/json" \
            "${ARKCASE_URL}/api/v1/service/note/COMPLAINT/${CASE_ID}" 2>/dev/null)
    fi
else
    CASE_JSON="{}"
    NOTES_JSON="[]"
fi

# 3. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Construct Result JSON
# Use python to safely construct JSON with escaped strings
python3 -c "
import json
import os
import sys

try:
    case_data = json.loads('''$CASE_JSON''')
except:
    case_data = {}

try:
    notes_data = json.loads('''$NOTES_JSON''')
    if not isinstance(notes_data, list):
        notes_data = []
except:
    notes_data = []

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'case_id': '$CASE_ID',
    'initial_note_count': int('$INITIAL_NOTE_COUNT'),
    'final_status': case_data.get('status', 'UNKNOWN'),
    'final_notes': notes_data,
    'screenshot_path': '/tmp/task_final.png',
    'screenshot_exists': os.path.exists('/tmp/task_final.png')
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json