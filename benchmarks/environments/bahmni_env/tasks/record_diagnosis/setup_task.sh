#!/bin/bash
set -e

echo "=== Setting up record_diagnosis task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record Task Start Time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Ensure Bahmni/OpenMRS is ready
if ! wait_for_bahmni 600; then
    echo "ERROR: Bahmni API is not reachable."
    exit 1
fi

# 3. Get Patient UUID
PATIENT_ID="BAH000005"
PATIENT_UUID=$(get_patient_uuid_by_identifier "$PATIENT_ID")

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Patient $PATIENT_ID not found. Ensuring seed data..."
    # Attempt to run seed script if patient missing (fallback)
    python3 /workspace/scripts/seed_bahmni.py --base-url "$OPENMRS_BASE_URL" --username "$BAHMNI_ADMIN_USERNAME" --password "$BAHMNI_ADMIN_PASSWORD"
    PATIENT_UUID=$(get_patient_uuid_by_identifier "$PATIENT_ID")
fi

if [ -z "$PATIENT_UUID" ]; then
    echo "CRITICAL ERROR: Could not find patient $PATIENT_ID even after seeding."
    exit 1
fi
echo "Target Patient: $PATIENT_ID (UUID: $PATIENT_UUID)"
echo "$PATIENT_UUID" > /tmp/patient_uuid.txt

# 4. Ensure an Active Visit exists
# We create an active OPD visit so the agent can immediately enter consultation.
# Bahmni allows creating a visit via UI, but having one ready reduces friction/ambiguity.
echo "Checking/Creating active visit..."

# Check for active visit (stopDatetime is null)
ACTIVE_VISIT=$(openmrs_api_get "/visit?patient=${PATIENT_UUID}&includeInactive=false&v=default")
VISIT_COUNT=$(echo "$ACTIVE_VISIT" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('results', [])))")

if [ "$VISIT_COUNT" -eq "0" ]; then
    echo "No active visit found. Creating one..."
    
    # Get required UUIDs for visit creation
    LOC_UUID=$(openmrs_api_get "/location?tag=Login+Location&v=default" | python3 -c "import sys, json; print(json.load(sys.stdin)['results'][0]['uuid'])")
    TYPE_UUID=$(openmrs_api_get "/visittype?v=default" | python3 -c "import sys, json; print(json.load(sys.stdin)['results'][0]['uuid'])")
    
    # Create Visit Payload
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000+0000")
    PAYLOAD=$(cat <<EOF
{
    "patient": "$PATIENT_UUID",
    "visitType": "$TYPE_UUID",
    "location": "$LOC_UUID",
    "startDatetime": "$NOW"
}
EOF
)
    # Post to create visit
    openmrs_api_post "/visit" "$PAYLOAD" > /dev/null
    echo "Active visit created."
else
    echo "Active visit already exists."
fi

# 5. Record Initial Diagnoses State (Anti-gaming)
# We capture existing diagnoses to ensure we don't score pre-existing data.
INITIAL_DIAGNOSES=$(openmrs_api_get "/bahmnicore/diagnosis/search?patientUuid=${PATIENT_UUID}")
echo "$INITIAL_DIAGNOSES" > /tmp/initial_diagnoses.json

# 6. Prepare Browser
echo "Launching Browser..."
# Restart browser to ensure clean state and dismiss SSL warning
start_browser "$BAHMNI_LOGIN_URL"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="