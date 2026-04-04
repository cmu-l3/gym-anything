#!/bin/bash
echo "=== Exporting update_service_price result ==="

source /workspace/scripts/task_utils.sh

# Target ID defined in setup
DOC_ID="pricing_task_target_001"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_REV=$(cat /tmp/initial_doc_rev.txt 2>/dev/null || echo "")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Query the specific document from CouchDB
echo "Fetching document $DOC_ID..."
DOC_JSON=$(hr_couch_get "$DOC_ID")

# 3. Extract relevant fields using Python
# We extract name, price, and _rev. If doc is missing, fields will be null/empty.
PARSED_RESULT=$(echo "$DOC_JSON" | python3 -c "
import sys, json
try:
    doc = json.load(sys.stdin)
    # Check if doc exists (CouchDB returns error object if not found)
    if 'error' in doc:
        print(json.dumps({'exists': False}))
    else:
        data = doc.get('data', {})
        print(json.dumps({
            'exists': True,
            'id': doc.get('_id'),
            'rev': doc.get('_rev'),
            'name': data.get('name'),
            'price': data.get('price')
        }))
except Exception as e:
    print(json.dumps({'exists': False, 'error': str(e)}))
")

# 4. Search for DUPLICATE items (Anti-gaming)
# If the agent created a NEW item instead of updating, there might be 
# a doc with the expected name but wrong ID.
POTENTIAL_DUPLICATES=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | python3 -c "
import sys, json
target_name = 'Standard GP Consultation'
target_id = '$DOC_ID'
data = json.load(sys.stdin)
dupes = []
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc)
    # Check name match
    if d.get('name', '').lower() == target_name.lower():
        # If it's not our original ID, it's a duplicate/new creation
        if row.get('id') != target_id:
            dupes.append(row.get('id'))
print(json.dumps(dupes))
")

# 5. Compile full result
cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "initial_rev": "$INITIAL_REV",
    "target_doc": $PARSED_RESULT,
    "duplicates": $POTENTIAL_DUPLICATES,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="