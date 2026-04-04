#!/bin/bash
set -e

echo "=== Setting up add_concept_mapping task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Bahmni/OpenMRS to be ready
if ! wait_for_bahmni 600; then
    echo "ERROR: Bahmni/OpenMRS not reachable"
    exit 1
fi

# 1. Ensure 'SNOMED CT' Concept Source exists
log "Checking for SNOMED CT concept source..."
SOURCE_CHECK=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/conceptsource?q=SNOMED+CT&v=default" | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('results',[])))" 2>/dev/null || echo "0")

if [ "$SOURCE_CHECK" == "0" ]; then
  log "Creating SNOMED CT concept source..."
  curl -sk -X POST -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "SNOMED CT",
      "description": "Systematized Nomenclature of Medicine -- Clinical Terms",
      "hl7Code": "SCT"
    }' \
    "${OPENMRS_API_URL}/conceptsource" > /dev/null
fi

# 2. Ensure 'SAME-AS' Map Type exists
log "Checking for SAME-AS map type..."
TYPE_CHECK=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/conceptmaptype?q=SAME-AS&v=default" | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('results',[])))" 2>/dev/null || echo "0")

if [ "$TYPE_CHECK" == "0" ]; then
  log "Creating SAME-AS map type..."
  curl -sk -X POST -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "SAME-AS",
      "description": "Map between identical concepts"
    }' \
    "${OPENMRS_API_URL}/conceptmaptype" > /dev/null
fi

# 3. Get 'Malaria' concept UUID
log "Fetching Malaria concept UUID..."
MALARIA_UUID=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/concept?q=Malaria&v=default" | \
  python3 -c "import json,sys; d=json.load(sys.stdin); r=d.get('results',[]); print(r[0]['uuid'] if r else '')" 2>/dev/null)

if [ -z "$MALARIA_UUID" ]; then
  echo "ERROR: 'Malaria' concept not found in dictionary!"
  exit 1
fi
echo "$MALARIA_UUID" > /tmp/malaria_concept_uuid.txt
log "Malaria UUID: $MALARIA_UUID"

# 4. Remove any existing mapping to SNOMED CT:61462000 on Malaria (Clean State)
log "Cleaning up any existing target mappings..."
curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/concept/${MALARIA_UUID}?v=full" > /tmp/malaria_concept_full.json

# Use Python to find UUIDs of mappings to delete
MAPPINGS_TO_DELETE=$(python3 -c "
import json, sys
try:
    with open('/tmp/malaria_concept_full.json') as f:
        data = json.load(f)
    mappings = data.get('mappings', [])
    to_delete = []
    for m in mappings:
        term = m.get('conceptReferenceTerm', {})
        code = term.get('code', '')
        source = term.get('conceptSource', {}).get('display', '')
        # Check leniently for source name
        if code == '61462000' and 'SNOMED' in source:
            to_delete.append(m['uuid'])
    print(' '.join(to_delete))
except Exception as e:
    print('')
")

if [ -n "$MAPPINGS_TO_DELETE" ]; then
  log "Found pre-existing mappings to delete: $MAPPINGS_TO_DELETE"
  # OpenMRS REST API allows deleting concept maps directly if we have the map UUID
  # Note: The endpoint is often nested or requires specific handling, but we can try direct delete on the concept map resource if available,
  # or update the concept. The safest way via API without complex PUT payload is usually not exposed easily for sub-resources.
  # We will use a direct DB cleanup for reliability in this setup script since we have DB access.
  
  for map_uuid in $MAPPINGS_TO_DELETE; do
      log "Purging map UUID via DB: $map_uuid"
      docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -e "DELETE FROM concept_map WHERE uuid = '${map_uuid}';" 2>/dev/null || true
  done
else
  log "No pre-existing mappings found."
fi

# 5. Launch Browser
log "Launching browser..."
start_browser "${BAHMNI_BASE_URL}/openmrs/admin" 4

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="