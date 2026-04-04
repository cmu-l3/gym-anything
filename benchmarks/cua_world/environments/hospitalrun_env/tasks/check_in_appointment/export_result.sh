#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Query CouchDB for the specific appointment
# We look for the document we seeded: appointment_p1_alice_9am
echo "Fetching appointment state..."
APPT_DOC=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/appointment_p1_alice_9am")

# Extract relevant fields using python (safer than grep/jq inside minimal containers)
# We want: status, _rev (to check modification)
python3 -c "
import sys, json
try:
    doc = json.loads('$APPT_DOC')
    data = doc.get('data', {})
    
    # Check if this is the right doc (sanity check)
    is_alice = 'alicejohnson' in data.get('patient', '')
    
    # Output result
    result = {
        'exists': '_id' in doc,
        'status': data.get('status', 'Unknown'),
        'patient': data.get('patient', ''),
        'rev': doc.get('_rev', ''),
        'timestamp': $TASK_END
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > /tmp/appt_status.json

# Check if application (Firefox) is still running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Create final result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "appointment_data": $(cat /tmp/appt_status.json)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json