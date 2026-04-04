#!/bin/bash
echo "=== Setting up add_concept_synonym task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Bahmni/OpenMRS is reachable
if ! wait_for_bahmni 600; then
  echo "ERROR: Bahmni is not reachable"
  exit 1
fi

CONCEPT_UUID="5085AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
TARGET_SYNONYM="SBP"

# 1. Check if the concept exists
echo "Checking for concept $CONCEPT_UUID..."
CONCEPT_JSON=$(openmrs_api_get "/concept/${CONCEPT_UUID}?v=full")
if echo "$CONCEPT_JSON" | grep -q "Object with given uuid doesn't exist"; then
    echo "ERROR: Vital signs concept not found. System may be corrupted."
    exit 1
fi

# 2. CLEANUP: Ensure 'SBP' is NOT already a synonym
# If it exists, we must remove it so the agent has work to do.
# OpenMRS REST API doesn't allow deleting a single name easily via simple DELETE.
# We have to post the concept back without that specific name.

echo "Checking for existing synonym '$TARGET_SYNONYM'..."
HAS_SYNONYM=$(echo "$CONCEPT_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
names = data.get('names', [])
found = False
for name in names:
    if name.get('name') == '$TARGET_SYNONYM' and not name.get('voided'):
        found = True
        break
print('true' if found else 'false')
")

if [ "$HAS_SYNONYM" = "true" ]; then
    echo "Synonym '$TARGET_SYNONYM' exists. Removing it to prepare task state..."
    
    # Construct payload to void the specific name
    # We find the UUID of the name 'SBP' and void it
    NAME_UUID=$(echo "$CONCEPT_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
names = data.get('names', [])
for name in names:
    if name.get('name') == '$TARGET_SYNONYM' and not name.get('voided'):
        print(name.get('uuid'))
        break
")
    
    if [ -n "$NAME_UUID" ]; then
        # Delete/Void the name via sub-resource endpoint if available, 
        # or just generic delete on the name uuid
        # DELETE /concept/{concept_uuid}/name/{name_uuid}
        echo "Voiding name UUID: $NAME_UUID"
        curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
             -X DELETE \
             "${OPENMRS_API_URL}/concept/${CONCEPT_UUID}/name/${NAME_UUID}"
        sleep 2
    fi
fi

# 3. Start Browser at Login Page
echo "Starting browser..."
stop_browser
start_browser "$BAHMNI_LOGIN_URL" 4

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="