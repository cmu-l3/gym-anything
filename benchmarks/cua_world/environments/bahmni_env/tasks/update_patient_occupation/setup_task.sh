#!/bin/bash
set -e
echo "=== Setting up update_patient_occupation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Wait for Bahmni to be ready
wait_for_bahmni 600

# 2. Ensure 'Occupation' Person Attribute Type exists
echo "Checking for 'Occupation' attribute type..."
# Get UUID if it exists
ATTR_TYPE_UUID=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/personattributetype?q=Occupation&v=default" 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); r=d.get('results',[]); print(r[0]['uuid'] if r else '')")

# Create if not exists
if [ -z "$ATTR_TYPE_UUID" ]; then
  echo "Creating 'Occupation' attribute type..."
  PAYLOAD='{
    "name": "Occupation",
    "format": "java.lang.String",
    "description": "Patient occupation",
    "searchable": true
  }'
  ATTR_TYPE_UUID=$(curl -sk -X POST -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    -H "Content-Type: application/json" -d "$PAYLOAD" \
    "${OPENMRS_API_URL}/personattributetype" 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('uuid',''))")
fi
echo "Attribute Type UUID: $ATTR_TYPE_UUID"

# 3. Get Patient 'James Osei' (BAH000011)
# Note: In the seeded environment, James Osei is usually BAH000011, but we look up by identifier to be safe
PATIENT_IDENTIFIER="BAH000011"
echo "Finding patient $PATIENT_IDENTIFIER..."
PATIENT_UUID=$(get_patient_uuid_by_identifier "$PATIENT_IDENTIFIER" || true)

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Patient $PATIENT_IDENTIFIER not found. Seeding may have failed."
    # Fallback to search by name just in case ID is different
    PATIENT_UUID=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
      "${OPENMRS_API_URL}/patient?q=James+Osei&v=default" 2>/dev/null \
      | python3 -c "import json,sys; d=json.load(sys.stdin); r=d.get('results',[]); print(r[0]['uuid'] if r else '')")
fi

if [ -z "$PATIENT_UUID" ]; then
    echo "CRITICAL ERROR: Could not find patient James Osei"
    exit 1
fi
echo "Patient UUID: $PATIENT_UUID"

# 4. Set Initial State: Occupation = "Unemployed"
# First, find any existing attribute of this type and void it to ensure clean state
EXISTING_ATTR_UUID=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/person/${PATIENT_UUID}" 2>/dev/null \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
attrs=d.get('attributes',[])
target_uuid='$ATTR_TYPE_UUID'
found=''
for a in attrs:
    if a.get('attributeType',{}).get('uuid') == target_uuid and not a.get('voided'):
        found = a['uuid']
        break
print(found)
")

if [ -n "$EXISTING_ATTR_UUID" ]; then
  echo "Voiding existing occupation attribute ($EXISTING_ATTR_UUID)..."
  curl -sk -X DELETE -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/person/${PATIENT_UUID}/attribute/${EXISTING_ATTR_UUID}" 2>/dev/null || true
fi

echo "Setting initial occupation to 'Unemployed'..."
PAYLOAD="{\"attributeType\": \"$ATTR_TYPE_UUID\", \"value\": \"Unemployed\"}"
curl -sk -X POST -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  -H "Content-Type: application/json" -d "$PAYLOAD" \
  "${OPENMRS_API_URL}/person/${PATIENT_UUID}/attribute" > /dev/null

# 5. Save Context for Export Script
# We save the UUIDs so the export script knows exactly who/what to query
cat > /tmp/task_context.json <<EOF
{
  "patient_uuid": "$PATIENT_UUID",
  "attribute_type_uuid": "$ATTR_TYPE_UUID",
  "initial_value": "Unemployed"
}
EOF

# 6. Start Browser at Login Page
restart_browser "$BAHMNI_LOGIN_URL" 4

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="