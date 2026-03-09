#!/bin/bash
echo "=== Exporting Create Concept Source Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Query OpenMRS API for the ICD-11 Concept Source
echo "Querying API for ICD-11..."
API_RESPONSE=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/conceptsource?q=ICD-11&v=full" 2>/dev/null || echo "{}")

# Save raw response for debugging
echo "$API_RESPONSE" > /tmp/api_response_debug.json

# 2. Parse details from response using Python
# We extract the first result that matches "ICD-11" roughly to check details
PARSED_RESULT=$(python3 -c "
import sys, json
try:
    data = json.load(open('/tmp/api_response_debug.json'))
    results = data.get('results', [])
    
    # Find exact match or best candidate
    target = next((r for r in results if 'ICD-11' in r.get('name', '')), None)
    
    if target:
        output = {
            'found': True,
            'uuid': target.get('uuid'),
            'name': target.get('name'),
            'description': target.get('description'),
            'hl7Code': target.get('hl7Code'),
            'dateCreated': target.get('auditInfo', {}).get('dateCreated', ''),
            'retired': target.get('retired', False)
        }
    else:
        output = {'found': False}
    
    print(json.dumps(output))
except Exception as e:
    print(json.dumps({'found': False, 'error': str(e)}))
")

# 3. Get Current Total Count
CURRENT_COUNT=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/conceptsource?limit=1" 2>/dev/null \
    | python3 -c "import sys, json; print(json.load(sys.stdin).get('totalCount', 0))" 2>/dev/null || echo "0")

if [ "$CURRENT_COUNT" == "0" ] || [ -z "$CURRENT_COUNT" ]; then
     CURRENT_COUNT=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/conceptsource?v=default&limit=100" 2>/dev/null \
    | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('results', [])))" 2>/dev/null || echo "0")
fi

INITIAL_COUNT=$(cat /tmp/initial_source_count.txt 2>/dev/null || echo "0")

# 4. Construct Final JSON Result
# Using jq or python to combine variables into valid JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import os

try:
    parsed = json.loads('''$PARSED_RESULT''')
    result = {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'initial_count': int('$INITIAL_COUNT'),
        'current_count': int('$CURRENT_COUNT'),
        'source_data': parsed,
        'screenshot_path': '/tmp/task_final.png'
    }
    print(json.dumps(result, indent=2))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > "$TEMP_JSON"

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="