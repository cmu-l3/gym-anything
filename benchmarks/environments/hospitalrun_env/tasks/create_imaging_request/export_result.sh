#!/bin/bash
echo "=== Exporting create_imaging_request results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Fetch all imaging documents from CouchDB
# We fetch everything and let the python verifier filter by ID/Timestamp
echo "Fetching imaging documents..."
curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" > /tmp/all_docs.json

# Filter for imaging docs using python to be safe about data structure
python3 -c "
import json
import sys

try:
    with open('/tmp/all_docs.json', 'r') as f:
        data = json.load(f)
    
    imaging_docs = []
    for row in data.get('rows', []):
        doc = row.get('doc', {})
        # HospitalRun docs are often wrapped in a 'data' property, but 'type' might be at root
        # We check both locations for 'type': 'imaging'
        doc_type = doc.get('type') or doc.get('data', {}).get('type')
        
        if doc_type == 'imaging':
            imaging_docs.append(doc)
            
    with open('/tmp/imaging_docs.json', 'w') as f:
        json.dump(imaging_docs, f, indent=2)
        
    print(f'Exported {len(imaging_docs)} imaging documents')
except Exception as e:
    print(f'Error processing docs: {e}')
"

# 4. Construct Result JSON
# We bundle the docs and the initial ID list so the verifier can diff them
cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_imaging_ids": $(cat /tmp/initial_imaging_ids.json 2>/dev/null || echo "[]"),
    "final_imaging_docs": $(cat /tmp/imaging_docs.json 2>/dev/null || echo "[]"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions for copy_from_env
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json