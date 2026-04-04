#!/bin/bash
echo "=== Exporting task results ==="

HR_COUCH_URL="http://couchadmin:test@localhost:5984"
HR_COUCH_MAIN_DB="main"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Fetch the specific inventory item from DB
# We look for "Amoxicillin 500mg"
echo "Querying Database for 'Amoxicillin 500mg'..."

DOC_JSON=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    found = None
    for row in data.get('rows', []):
        doc = row.get('doc', {})
        name = doc.get('name') or doc.get('data', {}).get('name')
        if name == 'Amoxicillin 500mg':
            found = doc
            break
    print(json.dumps(found) if found else '{}')
except Exception as e:
    print(json.dumps({'error': str(e)}))
")

# Check if app is running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Create result JSON
# We extract key fields for the verifier
RESULT_JSON=$(echo "$DOC_JSON" | python3 -c "
import sys, json
doc = json.load(sys.stdin)
res = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'app_running': $APP_RUNNING,
    'doc_found': False
}

if doc and 'error' not in doc and doc != {}:
    res['doc_found'] = True
    # Normalize fields (HospitalRun uses 'data' wrapper sometimes)
    data = doc.get('data', doc)
    res['current_price'] = data.get('price')
    res['current_reorder_point'] = data.get('reorderPoint')
    res['current_name'] = data.get('name')
    res['doc_id'] = doc.get('_id')
    res['_rev'] = doc.get('_rev')

print(json.dumps(res))
")

# Save to tmp file with permissions
echo "$RESULT_JSON" > /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json