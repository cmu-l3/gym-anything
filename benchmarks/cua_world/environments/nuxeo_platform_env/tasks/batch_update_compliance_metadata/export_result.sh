#!/bin/bash
# Export script for batch_update_compliance_metadata
# Queries the final state of the documents via REST API and saves to JSON

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Documents to check
DOCS=(
    "/default-domain/workspaces/Projects/Annual-Report-2023"
    "/default-domain/workspaces/Projects/Project-Proposal"
    "/default-domain/workspaces/Projects/Q3-Status-Report"
)

# Initialize Python script to build the result JSON
# We use python to safely handle JSON encoding of API responses
python3 -c "
import sys
import json
import subprocess
import time

def get_doc_metadata(path):
    cmd = ['curl', '-s', '-u', '$NUXEO_AUTH', 
           'http://localhost:8080/nuxeo/api/v1/path' + path]
    try:
        result = subprocess.check_output(cmd).decode('utf-8')
        data = json.loads(result)
        props = data.get('properties', {})
        
        # Parse modification time
        mod_str = props.get('dc:modified', '')
        mod_ts = 0
        if mod_str:
            # Simple ISO parse attempt (e.g. 2023-10-27T10:00:00.00Z)
            # We'll just pass the string to verifier to handle parsing
            pass
            
        return {
            'path': path,
            'uid': data.get('uid'),
            'type': data.get('type'),
            'properties': {
                'dc:source': props.get('dc:source'),
                'dc:rights': props.get('dc:rights'),
                'dc:coverage': props.get('dc:coverage'),
                'dc:format': props.get('dc:format'),
                'dc:modified': mod_str
            }
        }
    except Exception as e:
        return {'path': path, 'error': str(e)}

docs = [
    '/default-domain/workspaces/Projects/Annual-Report-2023',
    '/default-domain/workspaces/Projects/Project-Proposal',
    '/default-domain/workspaces/Projects/Q3-Status-Report'
]

results = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'documents': [get_doc_metadata(d) for d in docs]
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f, indent=2)
"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_final.png 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="