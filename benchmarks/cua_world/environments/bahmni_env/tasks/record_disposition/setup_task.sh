#!/bin/bash
set -u
echo "=== Setting up Record Disposition Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Verify Bahmni/OpenMRS Readiness
if ! wait_for_bahmni 600; then
    echo "ERROR: Bahmni API not reachable"
    exit 1
fi

# 3. Identify Target Patient (Amara Okonkwo)
PATIENT_ID="BAH000002"
PATIENT_UUID=$(get_patient_uuid_by_identifier "$PATIENT_ID")

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Patient $PATIENT_ID not found. Seeding may have failed."
    exit 1
fi
echo "Target Patient UUID: $PATIENT_UUID"

# 4. Record Initial Encounter Count
# We use this to verify a NEW encounter is created
INITIAL_ENCOUNTERS=$(openmrs_api_get "/encounter?patient=${PATIENT_UUID}&v=custom:(uuid)" | jq '.results | length')
echo "$INITIAL_ENCOUNTERS" > /tmp/initial_encounter_count.txt
echo "Initial encounter count: $INITIAL_ENCOUNTERS"

# 5. Ensure ACTIVE Visit Exists
# Bahmni Clinical requires an active visit to record a consultation.
# We check for an open visit (no stopDatetime).
OPEN_VISITS=$(openmrs_api_get "/visit?patient=${PATIENT_UUID}&includeInactive=false&v=default")
OPEN_VISIT_UUID=$(echo "$OPEN_VISITS" | jq -r '.results[0].uuid // empty')

if [ -z "$OPEN_VISIT_UUID" ]; then
    echo "No active visit found. Creating new active visit for $PATIENT_ID..."
    
    # Get required metadata for visit creation
    VISIT_TYPE_UUID=$(openmrs_api_get "/visittype" | jq -r '.results[0].uuid')
    LOCATION_UUID=$(openmrs_api_get "/location?tag=Login+Location" | jq -r '.results[0].uuid')
    
    if [ -z "$VISIT_TYPE_UUID" ] || [ -z "$LOCATION_UUID" ]; then
        echo "ERROR: Could not fetch VisitType or Location for visit creation."
        exit 1
    fi

    # Create visit via API
    START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
    PAYLOAD=$(cat <<EOF
{
    "patient": "$PATIENT_UUID",
    "visitType": "$VISIT_TYPE_UUID",
    "location": "$LOCATION_UUID",
    "startDatetime": "$START_TIME"
}
EOF
)
    CREATE_RESP=$(openmrs_api_post "/visit" "$PAYLOAD")
    OPEN_VISIT_UUID=$(echo "$CREATE_RESP" | jq -r '.uuid // empty')
    
    if [ -n "$OPEN_VISIT_UUID" ]; then
        echo "Successfully created active visit: $OPEN_VISIT_UUID"
    else
        echo "ERROR: Failed to create visit. Response: $CREATE_RESP"
        exit 1
    fi
else
    echo "Found existing active visit: $OPEN_VISIT_UUID"
fi

# 6. Launch Browser
# We start at the home page so the agent has to navigate
restart_browser "$BAHMNI_LOGIN_URL" 4

# 7. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="