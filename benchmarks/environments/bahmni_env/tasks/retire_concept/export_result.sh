#!/bin/bash
set -u

echo "=== Exporting retire_concept results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

TARGET_NAME="Duplicate Diagnosis Code"

echo "Querying concept status..."
# Fetch the concept details
API_RESPONSE=$(openmrs_api_get "/concept?q=${TARGET_NAME// /%20}&v=full")

# Save raw response for debugging
echo "$API_RESPONSE" > /tmp/concept_query_debug.json

# Extract relevant fields using Python for reliability
python3 -c "
import sys, json, os

try:
    data = json.load(open('/tmp/concept_query_debug.json'))
    results = data.get('results', [])
    
    # Find exact name match if multiple returned
    target_name = '$TARGET_NAME'.lower()
    concept = None
    for c in results:
        if c.get('display', '').lower() == target_name or \
           c.get('name', {}).get('display', '').lower() == target_name:
            concept = c
            break
            
    if not concept and results:
        concept = results[0] # Fallback
        
    result_data = {
        'found': False,
        'retired': False,
        'retireReason': '',
        'uuid': '',
        'auditInfo': {},
        'task_start': $TASK_START,
        'task_end': $TASK_END
    }

    if concept:
        result_data['found'] = True
        result_data['uuid'] = concept.get('uuid')
        result_data['retired'] = concept.get('retired', False)
        result_data['retireReason'] = concept.get('retireReason', '')
        result_data['auditInfo'] = concept.get('auditInfo', {})

    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result_data, f, indent=2)
        
except Exception as e:
    print(f'Error processing JSON: {e}')
    # Create empty failure result
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'found': False, 'error': str(e)}, f)
"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json