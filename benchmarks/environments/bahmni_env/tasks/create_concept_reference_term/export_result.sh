#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot (evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Query OpenMRS API for the created term
# We use Python for robust JSON handling and filtering
echo "Querying OpenMRS for created term..."

python3 -c "
import requests
import json
import os
import time
from requests.auth import HTTPBasicAuth

# Config
USERNAME = '${BAHMNI_ADMIN_USERNAME}'
PASSWORD = '${BAHMNI_ADMIN_PASSWORD}'
API_URL = '${OPENMRS_API_URL}'
TARGET_CODE = 'A00'

# Auth
auth = HTTPBasicAuth(USERNAME, PASSWORD)
requests.packages.urllib3.disable_warnings()

result_data = {
    'term_found': False,
    'term': {},
    'timestamp': time.time()
}

try:
    # Search for term
    resp = requests.get(f'{API_URL}/conceptreferenceterm?q={TARGET_CODE}&v=full', auth=auth, verify=False)
    
    if resp.status_code == 200:
        results = resp.json().get('results', [])
        
        # Filter for exact match and not retired
        active_terms = [
            t for t in results 
            if t.get('code') == TARGET_CODE and not t.get('retired')
        ]
        
        # Sort by creation date descending (newest first)
        # Note: OpenMRS dates are ISO strings, string sort works for ISO8601
        active_terms.sort(key=lambda x: x.get('dateCreated', ''), reverse=True)
        
        if active_terms:
            term = active_terms[0]
            result_data['term_found'] = True
            result_data['term'] = {
                'uuid': term.get('uuid'),
                'code': term.get('code'),
                'name': term.get('name'),
                'description': term.get('description'),
                'dateCreated': term.get('dateCreated'),
                'source_name': term.get('conceptSource', {}).get('name'),
                'retired': term.get('retired')
            }
            print(f'Found term: {term.get(\"name\")} ({term.get(\"code\")})')
        else:
            print('No active term found with code A00')
    else:
        print(f'API Error: {resp.status_code}')

except Exception as e:
    print(f'Export script error: {e}')
    result_data['error'] = str(e)

# Save to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result_data, f, indent=2)
"

# 3. Add task start timestamp to result
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
# Use jq or python to append to existing json (Python is safer here)
python3 -c "
import json
try:
    with open('/tmp/task_result.json', 'r') as f:
        data = json.load(f)
    data['task_start_timestamp'] = int($TASK_START)
    data['screenshot_path'] = '/tmp/task_final.png'
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(data, f, indent=2)
except Exception as e:
    print(e)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json
echo "=== Export complete ==="