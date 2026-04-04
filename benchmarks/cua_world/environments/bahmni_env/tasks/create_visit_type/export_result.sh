#!/bin/bash
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting create_visit_type results ==="

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Verification Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_visit_type_count.txt 2>/dev/null || echo "0")

# Fetch all visit types (full view to get descriptions and audit info)
echo "Fetching visit types from API..."
API_RESPONSE=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/visittype?v=full")

# Save API response for debugging/backup
echo "$API_RESPONSE" > /tmp/api_response.json

# Process data with Python to extract exact details
# We extract: specific target details, total count, and a list of all names for debugging
python3 -c "
import sys, json, time, datetime

try:
    data = json.load(open('/tmp/api_response.json'))
    results = data.get('results', [])
    
    current_count = len(results)
    
    target_name = 'Telehealth Consultation'
    found_visit = next((item for item in results if item.get('name') == target_name), None)
    
    visit_details = {}
    if found_visit:
        # Parse creation date (ISO 8601) to timestamp
        # OpenMRS format example: '2023-10-27T10:00:00.000+0000'
        created_str = found_visit.get('auditInfo', {}).get('dateCreated', '')
        created_ts = 0
        if created_str:
            try:
                # Remove colon in timezone if present for python < 3.7 compatibility or simplified parsing
                # Actually OpenMRS often returns +0000 which is standard.
                # We'll use a simple manual parse or a robust library if available, 
                # but for this environment, let's assume standard ISO.
                # Fallback: just check if string exists.
                pass 
            except:
                pass
        
        visit_details = {
            'exists': True,
            'uuid': found_visit.get('uuid'),
            'name': found_visit.get('name'),
            'description': found_visit.get('description'),
            'retired': found_visit.get('retired'),
            'date_created_iso': created_str
        }
    else:
        visit_details = {'exists': False}

    output = {
        'task_start_ts': $TASK_START,
        'initial_count': int('$INITIAL_COUNT'),
        'current_count': current_count,
        'target_visit_type': visit_details,
        'all_names': [r.get('name') for r in results]
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(output, f, indent=2)
        
except Exception as e:
    print(f'Error processing result: {e}', file=sys.stderr)
    # Create a minimal failure result
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e), 'exists': False}, f)
"

# 3. Handle Permissions (Ensure verifier can read it)
chmod 644 /tmp/task_result.json 2>/dev/null || true
chmod 644 /tmp/task_final.png 2>/dev/null || true

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export complete ==="