#!/bin/bash
set -e
echo "=== Setting up Create Concept Reference Term task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Ensure "ICD-10-WHO" concept source exists
# The agent needs this source to be available in the dropdown
echo "Checking/Creating ICD-10-WHO concept source..."
python3 -c "
import requests, json, sys
from requests.auth import HTTPBasicAuth

auth = HTTPBasicAuth('${BAHMNI_ADMIN_USERNAME}', '${BAHMNI_ADMIN_PASSWORD}')
headers = {'Content-Type': 'application/json'}
base_url = '${OPENMRS_API_URL}'

# Check if exists
try:
    resp = requests.get(f'{base_url}/conceptsource?q=ICD-10-WHO&v=default', auth=auth, verify=False)
    results = resp.json().get('results', [])
    source_exists = any(r['name'] == 'ICD-10-WHO' for r in results)
    
    if not source_exists:
        print('Creating ICD-10-WHO source...')
        payload = {
            'name': 'ICD-10-WHO',
            'description': 'International Classification of Diseases, 10th Revision, WHO version',
            'hl7Code': 'ICD-10'
        }
        requests.post(f'{base_url}/conceptsource', auth=auth, json=payload, verify=False)
    else:
        print('ICD-10-WHO source already exists.')
except Exception as e:
    print(f'Error checking source: {e}')
"

# 3. Clean up existing "A00" term if it exists (to prevent pre-existing success)
# We retire it so it's not "active"
echo "Cleaning up any existing 'A00' terms..."
python3 -c "
import requests, json, sys
from requests.auth import HTTPBasicAuth

auth = HTTPBasicAuth('${BAHMNI_ADMIN_USERNAME}', '${BAHMNI_ADMIN_PASSWORD}')
headers = {'Content-Type': 'application/json'}
base_url = '${OPENMRS_API_URL}'

try:
    # Search for A00
    resp = requests.get(f'{base_url}/conceptreferenceterm?q=A00&v=default', auth=auth, verify=False)
    results = resp.json().get('results', [])
    
    for term in results:
        # Check specific code match (search is fuzzy)
        if term.get('code') == 'A00' and not term.get('retired'):
            uuid = term['uuid']
            print(f'Retiring existing A00 term: {uuid}')
            requests.post(
                f'{base_url}/conceptreferenceterm/{uuid}', 
                auth=auth, 
                json={'retired': True, 'retireReason': 'Task Setup Cleanup'}, 
                verify=False
            )
except Exception as e:
    print(f'Error cleaning up terms: {e}')
"

# 4. Start Browser at Bahmni Home (User must navigate to Admin)
# We start at Home to force the 'Navigation' part of the task
echo "Starting browser..."
start_browser "${BAHMNI_LOGIN_URL}"

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="