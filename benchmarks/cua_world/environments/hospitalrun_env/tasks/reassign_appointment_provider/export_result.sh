#!/bin/bash
echo "=== Exporting reassign_appointment_provider result ==="

source /workspace/scripts/task_utils.sh

# Get task info
APPT_ID=$(cat /tmp/task_appt_id.txt 2>/dev/null || echo "appointment_p1_taskseed")
START_MS=$(cat /tmp/task_appt_start.txt 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Fetch the appointment document from CouchDB
echo "Fetching appointment document: $APPT_ID"
DOC_JSON=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${APPT_ID}")

# 2. Extract key fields using python
# We extract: provider, patient, startDate, _rev
RESULT_JSON=$(echo "$DOC_JSON" | python3 -c "
import sys, json
try:
    doc = json.load(sys.stdin)
    data = doc.get('data', doc)
    
    res = {
        'exists': '_id' in doc,
        'id': doc.get('_id'),
        'rev': doc.get('_rev'),
        'provider': data.get('provider', ''),
        'patient': data.get('patient', ''),
        'startDate': data.get('startDate', 0),
        'endDate': data.get('endDate', 0),
        'status': data.get('status', ''),
        'raw_doc': doc
    }
    print(json.dumps(res))
except Exception as e:
    print(json.dumps({'exists': False, 'error': str(e)}))
")

# 3. Take final screenshot
take_screenshot /tmp/reassign_final.png

# 4. Save result to /tmp/task_result.json
# Using temp file pattern to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "initial_start_ms": $START_MS,
    "appointment_doc": $RESULT_JSON,
    "screenshot_path": "/tmp/reassign_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported result:"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="