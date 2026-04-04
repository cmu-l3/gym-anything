#!/bin/bash
echo "=== Exporting register_inventory_vendor results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Query CouchDB for the Vendor
# We look for a doc with the name "Global Pharma Supplies"
echo "Querying database for vendor..."

# We use python to parse the JSON output from CouchDB and extract the relevant document
# This runs INSIDE the container, so it has access to localhost CouchDB
PYTHON_SCRIPT=$(cat <<EOF
import sys, json, os

try:
    # Read stdin (curl output)
    data = json.load(sys.stdin)
    
    target_name = "Global Pharma Supplies"
    found_docs = []
    
    for row in data.get('rows', []):
        doc = row.get('doc', {})
        # Handle HospitalRun's data wrapper if present
        content = doc.get('data', doc)
        
        name = content.get('name', '')
        if not name:
            name = content.get('vendorName', '')
            
        if target_name.lower() in str(name).lower():
            found_docs.append(content)

    # Prepare result
    result = {
        "found": len(found_docs) > 0,
        "count": len(found_docs),
        "documents": found_docs,
        "task_start_time": 0
    }
    
    # Try to read start time
    if os.path.exists('/tmp/task_start_time.txt'):
        with open('/tmp/task_start_time.txt', 'r') as f:
            result['task_start_time'] = int(f.read().strip())

    print(json.dumps(result, indent=2))

except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF
)

# Execute query and parse
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | \
    python3 -c "$PYTHON_SCRIPT" > /tmp/task_result.json

# 3. Add screenshot info
if [ -f /tmp/task_final.png ]; then
    # Use jq if available, otherwise python to append
    python3 -c "import json; d=json.load(open('/tmp/task_result.json')); d['screenshot_exists']=True; print(json.dumps(d))" > /tmp/task_result.json.tmp && mv /tmp/task_result.json.tmp /tmp/task_result.json
fi

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="