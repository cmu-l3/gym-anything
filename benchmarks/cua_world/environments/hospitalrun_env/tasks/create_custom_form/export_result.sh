#!/bin/bash
echo "=== Exporting create_custom_form results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Find the created custom form in CouchDB
echo "Searching for Fall Risk Assessment form in database..."
FORM_JSON=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" 2>/dev/null | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
found_doc = {}
for row in data.get('rows', []):
    doc = row.get('doc', {})
    if doc.get('name') == 'Fall Risk Assessment':
        found_doc = doc
        break
print(json.dumps(found_doc))
" 2>/dev/null || echo "{}")

# Check if document was created/modified during task
DOC_CREATED_DURING_TASK="false"
if [ "$FORM_JSON" != "{}" ]; then
    # We can't easily get creation time from CouchDB doc unless we check _rev or internal timestamps if available.
    # However, we deleted it in setup, so if it exists now, it must have been created during the task.
    DOC_CREATED_DURING_TASK="true"
    echo "Form document found."
else
    echo "Form document NOT found."
fi

# Check if HospitalRun is running
APP_RUNNING="false"
if pgrep -f "hospitalrun" > /dev/null || pgrep -f "ember" > /dev/null || docker ps | grep -q "hospitalrun"; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "form_doc": $FORM_JSON,
    "doc_created_during_task": $DOC_CREATED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="