#!/bin/bash
echo "=== Exporting Create Concept Results ==="

source /workspace/scripts/task_utils.sh

# Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_TIME=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query OpenMRS API for the concept
# We use v=full to get numeric ranges and detailed names
echo "Querying OpenMRS API for 'Patient Satisfaction Score'..."

API_RESPONSE=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/concept?q=Patient+Satisfaction+Score&v=full")

# Save raw response for debugging
echo "$API_RESPONSE" > /tmp/concept_query_raw.json

# Parse the response using Python to create a structured result JSON
# We look for the exact match on the name
python3 -c "
import sys, json, time

try:
    raw_data = json.load(open('/tmp/concept_query_raw.json'))
    results = raw_data.get('results', [])
    
    # Filter for the specific concept we want (closest match)
    target_name = 'Patient Satisfaction Score'
    found_concept = None
    
    for concept in results:
        # Check display name or any name in names list
        if concept.get('display', '').lower() == target_name.lower() or \
           concept.get('name', {}).get('display', '').lower() == target_name.lower():
            found_concept = concept
            break
            
    # If not found by display, check exact match in names array if available
    if not found_concept and results:
        # Just take the first result if it looks close, verifier will be strict
        found_concept = results[0]

    output = {
        'task_start_timestamp': $TASK_START,
        'export_timestamp': $EXPORT_TIME,
        'concept_found': False,
        'concept_data': {}
    }

    if found_concept:
        output['concept_found'] = True
        
        # Extract fields safely
        data = {}
        data['uuid'] = found_concept.get('uuid')
        data['retired'] = found_concept.get('retired', False)
        data['datatype'] = found_concept.get('datatype', {}).get('display', 'Unknown')
        data['concept_class'] = found_concept.get('conceptClass', {}).get('display', 'Unknown')
        
        # Numeric specific fields
        data['hi_absolute'] = found_concept.get('hiAbsolute')
        data['low_absolute'] = found_concept.get('lowAbsolute')
        data['units'] = found_concept.get('units')
        
        # Descriptions
        descs = found_concept.get('descriptions', [])
        data['description'] = descs[0].get('display') if descs else ''
        
        # Names (check for short name)
        names = found_concept.get('names', [])
        short_names = [n.get('display') for n in names if n.get('conceptNameType') == 'SHORT']
        data['short_names'] = short_names
        data['fully_specified_name'] = found_concept.get('name', {}).get('display')
        
        # Date created (OpenMRS returns ISO string usually)
        # We might need to fetch audit info if not in full view, but full view usually has auditInfo or similar
        # For simplicity, we trust the API existence check post-task-start if we cleared it before
        
        output['concept_data'] = data

    with open('/tmp/task_result.json', 'w') as f:
        json.dump(output, f, indent=2)
        
except Exception as e:
    print(f'Error processing JSON: {e}')
    # Write safe fallback
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e), 'concept_found': False}, f)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="