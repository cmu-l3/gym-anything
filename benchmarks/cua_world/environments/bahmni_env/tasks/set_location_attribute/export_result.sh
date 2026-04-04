#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query OpenMRS API for the result
echo "Querying OpenMRS API for Satellite Clinic..."
# Get Location UUID
LOC_UUID=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/location?q=Satellite+Clinic&v=default" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); r=d.get('results',[]); print(r[0]['uuid'] if r else '')" 2>/dev/null || echo "")

FOUND_VALUE=""
FOUND_ATTR_UUID=""
IS_VOIDED="true"
DATE_CREATED=""
DATE_CHANGED=""

if [ -n "$LOC_UUID" ]; then
    echo "Location found: $LOC_UUID"
    # Get full details
    curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
      "${OPENMRS_API_URL}/location/${LOC_UUID}?v=full" > /tmp/loc_result.json
    
    # Extract the specific attribute
    # We look for 'Facility Code' attribute type
    python3 -c "
import json, sys
try:
    data = json.load(open('/tmp/loc_result.json'))
    result = {
        'found': False,
        'value': None,
        'uuid': None,
        'voided': True,
        'dateCreated': None,
        'dateChanged': None
    }
    
    for attr in data.get('attributes', []):
        atype = attr.get('attributeType', {})
        # Match by name or uuid if we had it, name is safer here as ID might vary across installs
        if atype.get('display') == 'Facility Code' and not attr.get('voided'):
            result['found'] = True
            result['value'] = attr.get('value')
            result['uuid'] = attr.get('uuid')
            result['voided'] = attr.get('voided')
            result['dateCreated'] = attr.get('auditInfo', {}).get('dateCreated')
            result['dateChanged'] = attr.get('auditInfo', {}).get('dateChanged')
            break
            
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > /tmp/attr_data.json

else
    echo "Location not found!"
    echo "{}" > /tmp/attr_data.json
fi

# Construct final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "location_uuid": "$LOC_UUID",
    "attribute_data": $(cat /tmp/attr_data.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="