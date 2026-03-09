#!/bin/bash
# Export script for TEA Pattern Validation

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# Define API helper locally just in case
dhis2_api_get() {
    curl -s -u admin:district "http://localhost:8080/api/$1"
}

# 1. Capture Final Screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Extract Attribute Configuration
echo "Querying National PUI attribute..."
ATTR_JSON=$(dhis2_api_get "trackedEntityAttributes?filter=name:eq:National+PUI&fields=id,name,valueType,unique,pattern,generated&paging=false")

# 3. Extract Person Entity Type Configuration
echo "Querying Person Entity Type..."
# We need to see if the new attribute is assigned to 'Person'
# First get Person ID (usually 'Person' or 'nEenWmSyUEp' in demo, but we filter by name)
PERSON_TYPE_JSON=$(dhis2_api_get "trackedEntityTypes?filter=name:eq:Person&fields=id,name,trackedEntityTypeAttributes[trackedEntityAttribute[id],displayInList,mandatory]&paging=false")

# 4. Combine into a result object
python3 -c "
import json, sys

try:
    attr_response = json.loads('''$ATTR_JSON''')
    person_response = json.loads('''$PERSON_TYPE_JSON''')
    
    result = {
        'attribute_found': False,
        'attribute': {},
        'assigned_to_person': False,
        'display_in_list': False,
        'timestamp': '$(date +%s)'
    }

    # Process Attribute
    if attr_response.get('trackedEntityAttributes'):
        attr = attr_response['trackedEntityAttributes'][0]
        result['attribute_found'] = True
        result['attribute'] = attr
        attr_id = attr['id']

        # Process Assignment
        if person_response.get('trackedEntityTypes'):
            person = person_response['trackedEntityTypes'][0]
            # Check list of assigned attributes
            for tea_link in person.get('trackedEntityTypeAttributes', []):
                if tea_link.get('trackedEntityAttribute', {}).get('id') == attr_id:
                    result['assigned_to_person'] = True
                    result['display_in_list'] = tea_link.get('displayInList', False)
                    break
    
    print(json.dumps(result, indent=2))

except Exception as e:
    print(json.dumps({'error': str(e)}))
" > /tmp/task_result.json

# 5. Set Permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result preview:"
cat /tmp/task_result.json