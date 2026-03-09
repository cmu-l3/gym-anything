#!/bin/bash
echo "=== Setting up Restore Voided Encounter Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record Start Time
date +%s > /tmp/task_start_time.txt

# 2. Wait for Bahmni/OpenMRS
if ! wait_for_bahmni 600; then
  echo "ERROR: OpenMRS not ready"
  exit 1
fi

# 3. Identify Patient (Sarah Johnson - BAH000003)
# In the seed script, Sarah Johnson is the 3rd patient, so usually BAH000003.
PATIENT_UUID=$(get_patient_uuid_by_identifier "BAH000003")

if [ -z "$PATIENT_UUID" ]; then
  echo "WARNING: Patient BAH000003 not found, searching by name..."
  PATIENT_UUID=$(openmrs_api_get "/patient?q=Sarah+Johnson&v=default" | jq -r '.results[0].uuid // empty')
fi

if [ -z "$PATIENT_UUID" ]; then
  echo "ERROR: Patient Sarah Johnson not found. Is the environment seeded?"
  exit 1
fi

echo "Target Patient UUID: $PATIENT_UUID"

# 4. Get necessary UUIDs for creating an encounter
# Visit Type (OPD)
VISIT_TYPE_UUID=$(openmrs_api_get "/visittype?q=OPD&v=default" | jq -r '.results[0].uuid')
# Location (Registration Desk or similar)
LOCATION_UUID=$(openmrs_api_get "/location?v=default" | jq -r '.results[0].uuid')
# Encounter Type (Vitals)
ENCOUNTER_TYPE_UUID=$(openmrs_api_get "/encountertype?q=Vitals&v=default" | jq -r '.results[0].uuid')
# Provider (Super Man - currently logged in user context usually suffices, or fetch one)
PROVIDER_UUID=$(openmrs_api_get "/provider?q=superman&v=default" | jq -r '.results[0].uuid')

if [ -z "$ENCOUNTER_TYPE_UUID" ]; then
  echo "ERROR: 'Vitals' encounter type not found"
  exit 1
fi

# 5. Create an Active Visit (if needed)
# We create a new visit to ensure recent activity
NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
VISIT_PAYLOAD=$(cat <<EOF
{
  "patient": "$PATIENT_UUID",
  "visitType": "$VISIT_TYPE_UUID",
  "location": "$LOCATION_UUID",
  "startDatetime": "$NOW",
  "stopDatetime": "$NOW"
}
EOF
)
VISIT_RESP=$(openmrs_api_post "/visit" "$VISIT_PAYLOAD")
VISIT_UUID=$(echo "$VISIT_RESP" | jq -r '.uuid // empty')

if [ -z "$VISIT_UUID" ]; then
  # Fallback to existing active visit
  VISIT_UUID=$(openmrs_api_get "/visit?patient=$PATIENT_UUID&includeInactive=false" | jq -r '.results[0].uuid // empty')
fi

if [ -z "$VISIT_UUID" ]; then
  echo "ERROR: Could not create or find visit for patient"
  exit 1
fi

echo "Visit UUID: $VISIT_UUID"

# 6. Create the Vitals Encounter
# We add some dummy observations (Weight/Height) to make it realistic, 
# but for the purpose of voiding, an empty encounter with type Vitals is often enough.
# However, let's try to be robust.
ENCOUNTER_PAYLOAD=$(cat <<EOF
{
  "patient": "$PATIENT_UUID",
  "visit": "$VISIT_UUID",
  "encounterType": "$ENCOUNTER_TYPE_UUID",
  "encounterDatetime": "$NOW",
  "location": "$LOCATION_UUID",
  "provider": "$PROVIDER_UUID"
}
EOF
)

ENC_RESP=$(openmrs_api_post "/encounter" "$ENCOUNTER_PAYLOAD")
TARGET_ENC_UUID=$(echo "$ENC_RESP" | jq -r '.uuid // empty')

if [ -z "$TARGET_ENC_UUID" ]; then
  echo "ERROR: Failed to create encounter"
  echo "Response: $ENC_RESP"
  exit 1
fi

echo "Created Encounter UUID: $TARGET_ENC_UUID"
echo "$TARGET_ENC_UUID" > /tmp/target_encounter_uuid.txt

# 7. VOID the Encounter (The Setup Goal)
# To void in OpenMRS REST, we send a DELETE request. 
# purge=false (default) means void. purge=true means delete from DB.
echo "Voiding the encounter..."
curl -sk -X DELETE \
  -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
  "${OPENMRS_API_URL}/encounter/${TARGET_ENC_UUID}"

# Verify it is voided
CHECK_VOID=$(openmrs_api_get "/encounter/${TARGET_ENC_UUID}?includeAll=true")
IS_VOIDED=$(echo "$CHECK_VOID" | jq -r '.voided')

if [ "$IS_VOIDED" != "true" ]; then
  echo "ERROR: Failed to void encounter during setup"
  exit 1
fi

echo "Encounter $TARGET_ENC_UUID successfully voided."

# 8. Browser Setup
# Open the OpenMRS Admin Login page specifically, as the task is about the Admin UI
# The OpenMRS admin URL is usually /openmrs/login.htm or just /openmrs/admin
ADMIN_URL="${BAHMNI_BASE_URL}/openmrs/login.htm"

if ! start_browser "$ADMIN_URL" 4; then
  echo "ERROR: Browser failed to start"
  exit 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="