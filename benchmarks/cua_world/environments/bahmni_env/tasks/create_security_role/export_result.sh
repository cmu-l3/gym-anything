#!/bin/bash
# Export results for create_security_role task
source /workspace/scripts/task_utils.sh

echo "=== Exporting create_security_role results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final_state.png

# 2. Query the Role via API
# We query by name "Lab Technician"
echo "Querying OpenMRS API for 'Lab Technician' role..."
ROLE_JSON=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/role?q=Lab+Technician&v=full" 2>/dev/null)

# 3. Get total role count (to compare with initial)
# Note: This is a rough check as OpenMRS usually has >100 roles, simple list length might be capped.
# We rely primarily on the existence of the specific role.
FINAL_ROLE_COUNT_RAW=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/role?v=default&limit=1" 2>/dev/null)

# 4. Check timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_ROLE_COUNT=$(cat /tmp/initial_role_count.txt 2>/dev/null || echo "0")

# 5. Compile into Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import sys
import time

try:
    role_response = json.loads('''${ROLE_JSON}''')
    results = role_response.get('results', [])
    
    # Find exact match
    target_role = None
    for r in results:
        if r.get('display', '').lower() == 'lab technician' or r.get('name', '').lower() == 'lab technician':
            target_role = r
            break
            
    output = {
        'task_start': ${TASK_START},
        'task_end': ${TASK_END},
        'initial_role_count': int('${INITIAL_ROLE_COUNT}'),
        'role_found': target_role is not None,
        'role_data': target_role,
        'timestamp': time.time()
    }
    
    print(json.dumps(output, indent=2))
except Exception as e:
    print(json.dumps({'error': str(e), 'role_found': False}))
" > "$TEMP_JSON"

# 6. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="