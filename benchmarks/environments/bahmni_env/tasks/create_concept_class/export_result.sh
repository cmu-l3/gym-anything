#!/bin/bash
echo "=== Exporting create_concept_class results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query OpenMRS API to check for the concept class
echo "Querying OpenMRS API for 'PRAPARE Assessment'..."

API_RESPONSE=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/conceptclass?v=full" 2>/dev/null)

# 3. Process result with Python to extract specific fields safely
# We look for a class with the exact name "PRAPARE Assessment"
python3 -c "
import sys, json, time

try:
    api_data = json.loads('''$API_RESPONSE''')
    results = api_data.get('results', [])
    
    # Find the specific class
    target_class = next((item for item in results if item.get('name') == 'PRAPARE Assessment'), None)
    
    output = {
        'class_found': False,
        'name': None,
        'description': None,
        'abbreviation': None,
        'retired': None,
        'date_created': None,
        'uuid': None
    }
    
    if target_class:
        output['class_found'] = True
        output['name'] = target_class.get('name')
        output['description'] = target_class.get('description')
        output['abbreviation'] = target_class.get('abbreviation') or target_class.get('shortName') # OpenMRS sometimes varies field names in versions
        output['retired'] = target_class.get('retired')
        output['uuid'] = target_class.get('uuid')
        
        # Try to get audit info if available
        audit = target_class.get('auditInfo', {})
        output['date_created'] = audit.get('dateCreated')

    # Save to file
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(output, f, indent=2)
        
    print(json.dumps(output, indent=2))

except Exception as e:
    print(f'Error processing API response: {e}')
    # Write safe failure file
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'class_found': False, 'error': str(e)}, f)
"

# 4. Check if we need to set permissions (standard procedure)
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="