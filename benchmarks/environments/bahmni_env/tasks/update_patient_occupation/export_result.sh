#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Load context from setup
if [ -f /tmp/task_context.json ]; then
    PATIENT_UUID=$(python3 -c "import json; print(json.load(open('/tmp/task_context.json'))['patient_uuid'])")
    ATTR_TYPE_UUID=$(python3 -c "import json; print(json.load(open('/tmp/task_context.json'))['attribute_type_uuid'])")
    INITIAL_VALUE=$(python3 -c "import json; print(json.load(open('/tmp/task_context.json'))['initial_value'])")
else
    echo "ERROR: Context file missing"
    PATIENT_UUID=""
    ATTR_TYPE_UUID=""
    INITIAL_VALUE=""
fi

# 2. Query OpenMRS for Current State
echo "Querying current attribute value..."
CURRENT_VALUE=""
ATTR_UUID=""
ATTR_TIMESTAMP=""

if [ -n "$PATIENT_UUID" ] && [ -n "$ATTR_TYPE_UUID" ]; then
    # Fetch person attributes
    API_RESPONSE=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
        "${OPENMRS_API_URL}/person/${PATIENT_UUID}" 2>/dev/null)
    
    # Parse Python script to handle JSON safely
    read CURRENT_VALUE ATTR_UUID ATTR_TIMESTAMP <<< $(echo "$API_RESPONSE" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    attrs = data.get('attributes', [])
    target_type = '$ATTR_TYPE_UUID'
    found_val = 'None'
    found_uuid = 'None'
    found_ts = '0'
    
    # Find the active attribute of the correct type
    for a in attrs:
        if a.get('attributeType', {}).get('uuid') == target_type and not a.get('voided'):
            found_val = a.get('value', 'None')
            found_uuid = a.get('uuid', 'None')
            # Bahmni REST API typically returns ISO dates, but audit info might be nested
            # For simplicity, we'll verify existence and value. 
            # Verification of 'when' happens by checking if it changed from initial.
            break
            
    print(f\"{found_val} {found_uuid}\")
except Exception:
    print(\"None None\")
")
fi

echo "Current Value: $CURRENT_VALUE"

# 3. Capture Evidence
take_screenshot /tmp/task_final.png

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_uuid": "$PATIENT_UUID",
    "attribute_type_uuid": "$ATTR_TYPE_UUID",
    "initial_value": "$INITIAL_VALUE",
    "current_value": "$CURRENT_VALUE",
    "attribute_uuid": "$ATTR_UUID",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="