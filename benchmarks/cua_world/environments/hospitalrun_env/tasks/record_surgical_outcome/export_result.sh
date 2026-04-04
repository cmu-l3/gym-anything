#!/bin/bash
echo "=== Exporting record_surgical_outcome result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_REV=$(cat /tmp/initial_plan_rev.txt 2>/dev/null || echo "")

# 3. Query the Operative Plan from CouchDB
PLAN_ID="operative_plan_p1_lucassilva_hernia"
CURRENT_PLAN_JSON=$(hr_couch_get "$PLAN_ID")

# 4. Extract Key Fields
# We use python to safely parse JSON and handle missing fields
cat <<EOF | python3 > /tmp/parsed_result.json
import sys, json

try:
    doc = json.loads('''$CURRENT_PLAN_JSON''')
    data = doc.get('data', {})
    
    result = {
        "exists": True if doc.get('_id') else False,
        "id": doc.get('_id'),
        "rev": doc.get('_rev'),
        "initial_rev": "$INITIAL_REV",
        "status": data.get('status', ''),
        "notes": data.get('notes', ''),
        "operation_description": data.get('operationDescription', '')
    }
except Exception as e:
    result = {
        "exists": False,
        "error": str(e)
    }

print(json.dumps(result))
EOF

# 5. Check if modified
# Compare revs inside the python logic or here. 
# We'll let the verifier handle the logic, just export the raw data.

# 6. Create Final Export JSON
# Combine timestamps and CouchDB data
cat <<EOF > /tmp/task_result.json
{
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "plan_data": $(cat /tmp/parsed_result.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Clean up
rm -f /tmp/parsed_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="