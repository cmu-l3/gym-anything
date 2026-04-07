#!/bin/bash
set -e
echo "=== Setting up remove_patient_identifier task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Select or Seed a Target Patient
echo "Selecting target patient..."
# Try to find a patient that isn't voided
PATIENT_UUID=$(omrs_db_query "SELECT uuid FROM patient WHERE voided=0 LIMIT 1;")

if [ -z "$PATIENT_UUID" ]; then
    echo "No patients found. Seeding data..."
    bash /workspace/scripts/seed_data.sh
    PATIENT_UUID=$(omrs_db_query "SELECT uuid FROM patient WHERE voided=0 LIMIT 1;")
fi

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Failed to find or seed a patient."
    exit 1
fi

# Get Patient Name
PATIENT_NAME=$(omrs_db_query "SELECT CONCAT(given_name, ' ', family_name) FROM person_name pn JOIN patient p ON p.patient_id = pn.person_id WHERE p.uuid='$PATIENT_UUID' AND pn.preferred=1 AND pn.voided=0;")
echo "Target Patient: $PATIENT_NAME ($PATIENT_UUID)"

# 2. Identify 'Old Identification Number' Type
# Standard CIEL/RefApp UUID
ID_TYPE_UUID="8d79403a-c2cc-11de-8d13-0010c6dffd0f"
CHECK_TYPE=$(omrs_db_query "SELECT uuid FROM patient_identifier_type WHERE uuid='$ID_TYPE_UUID'")

if [ -z "$CHECK_TYPE" ]; then
    echo "Standard ID type not found, falling back to any secondary type..."
    # Get the second available ID type (assuming first is OpenMRS ID)
    ID_TYPE_UUID=$(omrs_db_query "SELECT uuid FROM patient_identifier_type LIMIT 1 OFFSET 1;")
fi
echo "Using ID Type UUID: $ID_TYPE_UUID"

# 3. Inject Erroneous Identifier via REST API
ERROR_ID="999-ERROR"
LOCATION_UUID="44c3efb0-2583-4c80-a79e-1f756a03c0a1" # Outpatient Clinic

echo "Injecting erroneous identifier '$ERROR_ID'..."
# Construct JSON payload
PAYLOAD=$(cat <<EOF
{
  "identifier": "$ERROR_ID",
  "identifierType": "$ID_TYPE_UUID",
  "location": "$LOCATION_UUID",
  "preferred": false
}
EOF
)

# Post to patient/{uuid}/identifier
omrs_post "/patient/$PATIENT_UUID/identifier" "$PAYLOAD" > /dev/null

# 4. Create Task Artifacts for Agent
echo "$PATIENT_NAME" > /home/ga/Desktop/task_patient.txt
echo "$PATIENT_UUID" > /tmp/target_patient_uuid.txt
echo "$ERROR_ID" > /tmp/target_identifier_value.txt

# 5. Launch Application
# Open Firefox directly to the patient's chart
TARGET_URL="http://localhost/openmrs/spa/patient/$PATIENT_UUID/chart/Patient%20Summary"
ensure_openmrs_logged_in "$TARGET_URL"

# 6. Capture Initial State
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="