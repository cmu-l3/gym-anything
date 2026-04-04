#!/bin/bash
set -u

echo "=== Exporting Create Relationship Type results ==="

source /workspace/scripts/task_utils.sh

# Record task end timestamp
date +%s > /tmp/task_end_timestamp.txt

# 1. Take final screenshot of the browser state
take_screenshot /tmp/task_final.png

# 2. Query OpenMRS for all relationship types (full view to see description and names)
echo "Querying OpenMRS for relationship types..."
API_RESPONSE=$(openmrs_api_get "/relationshiptype?v=full")

# Save raw response for debug
echo "$API_RESPONSE" > /tmp/api_response_debug.json

# 3. Get initial count
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_timestamp.txt 2>/dev/null || echo "0")

# 4. Prepare JSON result
# We construct a JSON object containing the API response and valid metadata
# Using Python to construct clean JSON to avoid bash quoting hell
python3 -c "
import json
import sys
import os
import time

try:
    api_response = json.load(open('/tmp/api_response_debug.json'))
    results = api_response.get('results', [])
    current_count = len(results)
except Exception as e:
    results = []
    current_count = 0
    print(f'Error parsing API response: {e}', file=sys.stderr)

initial_count = int('${INITIAL_COUNT}')
task_start = int('${TASK_START_TIME}')

output = {
    'initial_count': initial_count,
    'current_count': current_count,
    'task_start_timestamp': task_start,
    'relationship_types': results,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(output, f, indent=2)
"

# Set permissions so verifier can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json | head -n 20
echo "..."