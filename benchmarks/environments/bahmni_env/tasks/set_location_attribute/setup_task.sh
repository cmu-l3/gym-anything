#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up set_location_attribute task ==="

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
# Also in ISO format for easy reading
date -Iseconds > /tmp/task_start_iso.txt

# Ensure Bahmni/OpenMRS is ready
wait_for_bahmni 600

# 1. Ensure 'Facility Code' Attribute Type exists
echo "Checking for Facility Code attribute type..."
# Use python to parse JSON safely
ATTR_TYPE_UUID=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/locationattributetype?q=Facility+Code&v=default" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); r=d.get('results',[]); print(r[0]['uuid'] if r else '')" 2>/dev/null || echo "")

if [ -z "$ATTR_TYPE_UUID" ]; then
    echo "Creating Facility Code attribute type..."
    PAYLOAD='{
        "name": "Facility Code",
        "description": "Billing facility code",
        "datatypeClassname": "org.openmrs.customdatatype.datatype.FreeTextDatatype",
        "minOccurs": 0,
        "maxOccurs": 1
    }'
    ATTR_TYPE_UUID=$(curl -sk -X POST -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
      -H "Content-Type: application/json" -d "$PAYLOAD" \
      "${OPENMRS_API_URL}/locationattributetype" \
      | python3 -c "import json,sys; print(json.load(sys.stdin).get('uuid',''))")
fi
echo "Attribute Type UUID: $ATTR_TYPE_UUID"

# 2. Ensure 'Satellite Clinic' Location exists
echo "Checking for Satellite Clinic location..."
LOC_UUID=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/location?q=Satellite+Clinic&v=default" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); r=d.get('results',[]); print(r[0]['uuid'] if r else '')" 2>/dev/null || echo "")

if [ -z "$LOC_UUID" ]; then
    echo "Creating Satellite Clinic location..."
    PAYLOAD='{
        "name": "Satellite Clinic",
        "description": "Remote outpatient clinic"
    }'
    LOC_UUID=$(curl -sk -X POST -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
      -H "Content-Type: application/json" -d "$PAYLOAD" \
      "${OPENMRS_API_URL}/location" \
      | python3 -c "import json,sys; print(json.load(sys.stdin).get('uuid',''))")
fi
echo "Location UUID: $LOC_UUID"

# 3. Clean existing attributes on the location to ensure clean state
# We get full details to find existing attributes
if [ -n "$LOC_UUID" ]; then
    echo "Clearing existing attributes..."
    curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
      "${OPENMRS_API_URL}/location/${LOC_UUID}?v=full" > /tmp/loc_full.json

    # Parse python script to find attribute UUIDs for Facility Code and output them
    # We look for attributes where attributeType.uuid matches our target
    python3 -c "
import json, sys
try:
    data = json.load(open('/tmp/loc_full.json'))
    attr_type_uuid = '$ATTR_TYPE_UUID'
    to_void = []
    for attr in data.get('attributes', []):
        atype = attr.get('attributeType', {})
        # Check UUID or name match
        if (atype.get('uuid') == attr_type_uuid or atype.get('display') == 'Facility Code') and not attr.get('voided'):
            to_void.append(attr['uuid'])
    print(' '.join(to_void))
except Exception as e:
    print('')
    " > /tmp/attrs_to_void.txt

    ATTRS_TO_VOID=$(cat /tmp/attrs_to_void.txt)
    for auuid in $ATTRS_TO_VOID; do
        if [ -n "$auuid" ]; then
            echo "Voiding existing attribute: $auuid"
            curl -sk -X DELETE -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
              "${OPENMRS_API_URL}/location/${LOC_UUID}/attribute/${auuid}?purge=true" || true
        fi
    done
fi

# 4. Start Browser at OpenMRS Admin Page
ADMIN_URL="${BAHMNI_BASE_URL}/openmrs/admin"
echo "Starting browser at $ADMIN_URL..."
start_browser "$ADMIN_URL" 4

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="