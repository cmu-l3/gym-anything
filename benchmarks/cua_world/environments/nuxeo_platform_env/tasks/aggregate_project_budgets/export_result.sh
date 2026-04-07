#!/bin/bash
# Post-task export script
# Queries Nuxeo API to retrieve the created Note and exports it to a JSON file.

set -e
echo "=== Exporting aggregate_project_budgets results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Define paths
NOTE_PATH="/default-domain/workspaces/Projects/Q3-Infrastructure/Budget-Summary"
RESULT_JSON="/tmp/task_result.json"

# Initialize result variables
NOTE_EXISTS="false"
NOTE_CONTENT=""
NOTE_CREATED_AT=""
NOTE_CREATOR=""
HTTP_CODE="404"

# Query Nuxeo API for the result document
# We need to fetch properties to get the note content
RESPONSE=$(curl -s -w "\n%{http_code}" -u "$NUXEO_AUTH" \
    -H "Content-Type: application/json" \
    -H "X-NXproperties: *" \
    "$NUXEO_URL/api/v1/path$NOTE_PATH")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" = "200" ]; then
    NOTE_EXISTS="true"
    # Extract relevant fields using python
    # We extract note:note (content), dc:created (timestamp), dc:creator
    echo "$BODY" > /tmp/note_response.json
    
    python3 -c "
import json
try:
    with open('/tmp/note_response.json', 'r') as f:
        data = json.load(f)
    
    props = data.get('properties', {})
    content = props.get('note:note', '')
    created = props.get('dc:created', '')
    creator = props.get('dc:creator', '')
    type_ = data.get('type', '')
    
    result = {
        'exists': True,
        'content': content,
        'created_at': created,
        'creator': creator,
        'type': type_
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'exists': True, 'error': str(e)}))
" > /tmp/note_data.json

else
    echo '{"exists": false}' > /tmp/note_data.json
fi

# Assemble final JSON for verifier
python3 -c "
import json
import os

task_start = $TASK_START
task_end = $TASK_END

# Load note data
with open('/tmp/note_data.json', 'r') as f:
    note_data = json.load(f)

# Load ground truth (just to check if it exists, verifier does the comparison)
gt_exists = os.path.exists('/tmp/budget_ground_truth.txt')

final_result = {
    'task_start': task_start,
    'task_end': task_end,
    'note_data': note_data,
    'ground_truth_file_exists': gt_exists,
    'screenshot_path': '/tmp/task_final.png'
}

with open('$RESULT_JSON', 'w') as f:
    json.dump(final_result, f, indent=2)
"

# Set permissions so ga/verifier can read it
chmod 666 "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"
cat "$RESULT_JSON"